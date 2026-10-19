// Lofi Room matchmaking server: hands out invite codes and passes the WebRTC handshake between the host and guests.
// It never carries game traffic (the game picture, sound and controls go straight between the players).
// No dependencies: Node 18+.   Run:  node server.js        (PORT=8787 by default)
// Put it behind HTTPS (wss://) in production, e.g. Caddy / Cloudflare / fly.io / any host that terminates TLS for you.
"use strict";
const http = require("http");
const crypto = require("crypto");

const PORT = parseInt(process.env.PORT || "8787", 10);
const MAX_PLAYERS = parseInt(process.env.MAX_PLAYERS || "4", 10);     // including the host
const GRACE_MS = parseInt(process.env.GRACE_MS || "90000", 10);        // a host that dropped can take its code back this long
const JOIN_PER_MIN = parseInt(process.env.JOIN_PER_MIN || "12", 10);   // join attempts per address per minute
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";                    // no 0/O or 1/I
const CODE_LEN = 6;
const MAX_FRAME = 64 * 1024;
const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const rooms = new Map();        // code -> { code, ver, host: Client|null, guests: Map(id -> Client), hostName, dropAt }
const attempts = new Map();     // ip -> [timestamps]

// ------------------------------------------------------------------ a tiny RFC 6455 websocket

class Client {
	constructor(socket, ip) {
		this.socket = socket;
		this.ip = ip;
		this.buf = Buffer.alloc(0);
		this.frag = null;
		this.alive = true;
		this.pongAt = Date.now();
		this.role = null;       // "host" | "guest"
		this.room = null;
		this.id = 0;
		this.name = "";
		socket.on("data", (d) => this.onData(d));
		socket.on("close", () => this.onClose());
		socket.on("error", () => this.socket.destroy());
	}

	send(obj) {
		if (!this.alive) return;
		this.sendFrame(0x1, Buffer.from(JSON.stringify(obj)));
	}

	sendFrame(op, payload) {
		let head;
		if (payload.length < 126) head = Buffer.from([0x80 | op, payload.length]);
		else if (payload.length < 65536) { head = Buffer.alloc(4); head[0] = 0x80 | op; head[1] = 126; head.writeUInt16BE(payload.length, 2); }
		else { head = Buffer.alloc(10); head[0] = 0x80 | op; head[1] = 127; head.writeBigUInt64BE(BigInt(payload.length), 2); }
		try { this.socket.write(Buffer.concat([head, payload])); } catch (e) { /* closed */ }
	}

	close(code = 1000) {
		if (!this.alive) return;
		const p = Buffer.alloc(2); p.writeUInt16BE(code, 0);
		this.sendFrame(0x8, p);
		this.alive = false;
		this.socket.end();
		this.onClose();
	}

	onData(d) {
		this.buf = Buffer.concat([this.buf, d]);
		for (;;) {
			const b = this.buf;
			if (b.length < 2) return;
			const fin = (b[0] & 0x80) !== 0, op = b[0] & 0x0f, masked = (b[1] & 0x80) !== 0;
			let len = b[1] & 0x7f, off = 2;
			if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
			else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
			if (len > MAX_FRAME || !masked) { this.close(1009); return; }       // clients must mask; keep frames small
			if (b.length < off + 4 + len) return;
			const mask = b.subarray(off, off + 4);
			const payload = Buffer.from(b.subarray(off + 4, off + 4 + len));
			for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
			this.buf = b.subarray(off + 4 + len);
			if (op === 0x8) { this.close(1000); return; }
			if (op === 0x9) { this.sendFrame(0xA, payload); continue; }
			if (op === 0xA) { this.pongAt = Date.now(); continue; }
			if (op === 0x1 || op === 0x2) { this.frag = { op, parts: [payload] }; }
			else if (op === 0x0 && this.frag) { this.frag.parts.push(payload); }
			else continue;
			if (fin) {
				const whole = Buffer.concat(this.frag.parts);
				const isText = this.frag.op === 0x1;
				this.frag = null;
				if (isText && whole.length <= MAX_FRAME) onMessage(this, whole.toString("utf8"));
			}
		}
	}

	onClose() {
		if (this._closed) return;
		this._closed = true;
		this.alive = false;
		leave(this);
	}
}

// ------------------------------------------------------------------ rooms

function newCode() {
	for (let tries = 0; tries < 50; tries++) {
		let c = "";
		for (let i = 0; i < CODE_LEN; i++) c += ALPHABET[crypto.randomInt(ALPHABET.length)];
		if (!rooms.has(c)) return c;
	}
	return null;
}

function cleanName(n) {
	return String(n || "Guest").replace(/[^\p{L}\p{N} _.\-]/gu, "").trim().slice(0, 16) || "Guest";
}

function rateOk(ip) {
	const now = Date.now();
	const list = (attempts.get(ip) || []).filter((t) => now - t < 60000);
	list.push(now);
	attempts.set(ip, list);
	return list.length <= JOIN_PER_MIN;
}

function leave(c) {
	const room = c.room;
	if (!room) return;
	c.room = null;
	if (c.role === "host") {
		if (room.host === c) {
			room.host = null;
			room.dropAt = Date.now();
			for (const g of room.guests.values()) g.send({ t: "host_away" });
		}
	} else if (c.role === "guest") {
		if (room.guests.get(c.id) === c) {
			room.guests.delete(c.id);
			if (room.host) room.host.send({ t: "peer_leave", id: c.id });
		}
	}
}

function freeId(room) {
	for (let i = 2; i <= MAX_PLAYERS; i++) if (!room.guests.has(i)) return i;
	return 0;
}

function onMessage(c, text) {
	let m;
	try { m = JSON.parse(text); } catch (e) { return c.send({ t: "error", code: "bad" }); }
	if (!m || typeof m.t !== "string") return c.send({ t: "error", code: "bad" });
	switch (m.t) {
		case "ping": return c.send({ t: "pong" });
		case "host": return doHost(c, m);
		case "join": return doJoin(c, m);
		case "sig": return doSig(c, m);
		case "kick": return doKick(c, m);
		case "leave": return c.close(1000);
		default: return c.send({ t: "error", code: "bad" });
	}
}

function doHost(c, m) {
	if (c.room) return c.send({ t: "error", code: "bad" });
	const ver = parseInt(m.ver, 10) || 0;
	let room = null;
	const want = typeof m.code === "string" ? m.code.toUpperCase() : "";
	if (want && rooms.has(want) && !rooms.get(want).host) {      // taking a dropped room back (the host napped / reconnected)
		room = rooms.get(want);
		room.ver = ver;
	} else {
		const code = newCode();
		if (!code) return c.send({ t: "error", code: "busy" });
		room = { code, ver, host: null, guests: new Map(), hostName: "", dropAt: 0 };
		rooms.set(code, room);
	}
	room.host = c;
	room.dropAt = 0;
	room.hostName = cleanName(m.name);
	c.role = "host"; c.room = room; c.id = 1; c.name = room.hostName;
	c.send({ t: "hosted", code: room.code, id: 1, max: MAX_PLAYERS });
	for (const g of room.guests.values()) {                       // guests that waited for the host: tell the host about them again
		c.send({ t: "peer_join", id: g.id, name: g.name });
		g.send({ t: "host_back" });
	}
}

function doJoin(c, m) {
	if (c.room) return c.send({ t: "error", code: "bad" });
	if (!rateOk(c.ip)) return c.send({ t: "error", code: "rate" });
	const code = String(m.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
	const room = rooms.get(code);
	if (!room) return c.send({ t: "error", code: "no_room" });
	const ver = parseInt(m.ver, 10) || 0;
	if (ver !== room.ver) return c.send({ t: "error", code: "version", host_ver: room.ver });
	if (!room.host) return c.send({ t: "error", code: "host_away" });
	const id = freeId(room);
	if (!id) return c.send({ t: "error", code: "full" });
	c.role = "guest"; c.room = room; c.id = id; c.name = cleanName(m.name);
	room.guests.set(id, c);
	const peers = [{ id: 1, name: room.hostName }];
	for (const g of room.guests.values()) if (g !== c) peers.push({ id: g.id, name: g.name });
	c.send({ t: "joined", id, host_name: room.hostName, peers, code });
	room.host.send({ t: "peer_join", id, name: c.name });
}

function doSig(c, m) {
	const room = c.room;
	if (!room || typeof m.data !== "object" || m.data === null) return;
	const to = parseInt(m.to, 10);
	if (c.role === "host") {
		const g = room.guests.get(to);
		if (g) g.send({ t: "sig", from: 1, data: m.data });
	} else if (c.role === "guest" && to === 1 && room.host) {      // guests only talk to the host (star shape)
		room.host.send({ t: "sig", from: c.id, data: m.data });
	}
}

function doKick(c, m) {
	if (c.role !== "host" || !c.room) return;
	const g = c.room.guests.get(parseInt(m.id, 10));
	if (g) { g.send({ t: "kicked" }); g.close(1000); }
}

// ------------------------------------------------------------------ http + upgrade

const server = http.createServer((req, res) => {
	if (req.url === "/health") { res.writeHead(200, { "content-type": "text/plain" }); return res.end("ok"); }
	res.writeHead(200, { "content-type": "text/plain" });
	res.end("Lofi Room matchmaking server\n");
});

server.on("upgrade", (req, socket) => {
	const key = req.headers["sec-websocket-key"];
	if (!key || String(req.headers["upgrade"]).toLowerCase() !== "websocket") { socket.destroy(); return; }
	const accept = crypto.createHash("sha1").update(key + GUID).digest("base64");
	socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
	const ip = String(req.headers["x-forwarded-for"] || req.socket.remoteAddress || "").split(",")[0].trim();
	new Client(socket, ip);
});

const clients = new Set();
server.on("upgrade", (req, socket) => { /* tracked below via keepalive sweep */ });

setInterval(() => {            // keepalive + clean up rooms whose host never came back
	const now = Date.now();
	for (const [code, room] of rooms) {
		if (!room.host && room.dropAt && now - room.dropAt > GRACE_MS) {
			for (const g of room.guests.values()) { g.send({ t: "closed" }); g.close(1000); }
			rooms.delete(code);
		}
	}
	for (const [ip, list] of attempts) {
		const keep = list.filter((t) => now - t < 60000);
		if (keep.length) attempts.set(ip, keep); else attempts.delete(ip);
	}
}, 5000).unref();

module.exports = { server, rooms };
if (require.main === module) {
	server.listen(PORT, () => console.log("Lofi Room matchmaking server on port " + PORT));
}
