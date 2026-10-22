// Lofi Room matchmaking server: hands out invite codes and passes the WebRTC handshake between the host and guests.
// Game traffic normally goes straight between the players; when their networks won't allow that, it falls back
// to binary messages through this server ([to id] + packet in, [from id] + packet out), host <-> guests only.
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
const MAX_FRAME = 64 * 1024;                 // text (handshake) messages
const MAX_BIN = 1024 * 1024;                 // relayed game packets (a comic page can be a few hundred KB)
const RELAY_BPS = parseInt(process.env.RELAY_BPS || String(4 * 1024 * 1024), 10);   // per player, bytes a second
const RELAY_BACKLOG = 4 * 1024 * 1024;       // a receiver this far behind starts losing packets instead of piling up
const MAX_ROOMS = parseInt(process.env.MAX_ROOMS || "2000", 10);
const MAX_CONNS = parseInt(process.env.MAX_CONNS || "400", 10);
const MAX_CONNS_PER_IP = parseInt(process.env.MAX_CONNS_PER_IP || "8", 10);
const HOST_PER_MIN = parseInt(process.env.HOST_PER_MIN || "6", 10);        // rooms opened per address per minute
const ROOMS_PER_IP = parseInt(process.env.ROOMS_PER_IP || "3", 10);        // open (or held for a dropped host) at once
const MAX_PENDING = parseInt(process.env.MAX_PENDING || String(96 * 1024 * 1024), 10);   // half-received data, all players together
const PARTIAL_MS = 15000;                    // a message started this long ago and still not finished: the sender is stalling
const TRUST_PROXY = process.env.TRUST_PROXY === "1";
// Relay for players whose networks block a direct link (coturn with use-auth-secret). Optional.
const TURN_SECRET = process.env.TURN_SECRET || "";
const TURN_HOST = process.env.TURN_HOST || "";
function iceFor(id) {
	if (!TURN_SECRET || !TURN_HOST) return [];
	const user = `${Math.floor(Date.now() / 1000) + 12 * 3600}:p${id}`;     // good for 12 hours
	const credential = crypto.createHmac("sha1", TURN_SECRET).update(user).digest("base64");
	return [{ urls: [`turn:${TURN_HOST}:3478?transport=udp`, `turn:${TURN_HOST}:3478?transport=tcp`], username: user, credential }];
}             // only read X-Forwarded-For behind Caddy/nginx
const IDLE_MS = 70000;                                            // no pong for this long = gone
const clients = new Set();
const perIp = new Map();
const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const rooms = new Map();        // code -> { code, ver, ip, approve, host: Client|null, guests: Map(id -> Client), hostName, dropAt }
const attempts = new Map();     // ip -> [timestamps]
const hostings = new Map();     // ip -> [timestamps]
let pendingTotal = 0;           // bytes held in half-received messages

// ------------------------------------------------------------------ a tiny RFC 6455 websocket

class Client {
	constructor(socket, ip) {
		this.socket = socket;
		this.ip = ip;
		this.buf = Buffer.alloc(0);
		this.frag = null;
		this.alive = true;
		this.pongAt = Date.now();
		this.token = "";
		this.role = null;       // "host" | "guest"
		this.room = null;
		this.id = 0;
		this.name = "";
		this.budget = RELAY_BPS;
		this.budgetAt = Date.now();
		this.admitted = false;  // a guest the host has let in (rooms that ask first)
		this.held = 0;          // this client's share of pendingTotal
		this.partialAt = 0;
		socket.on("data", (d) => this.onData(d));
		socket.on("close", () => this.onClose());
		socket.on("error", () => this.socket.destroy());
		clients.add(this);
		perIp.set(ip, (perIp.get(ip) || 0) + 1);
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
		this.parse();
		if (!this.alive) return;
		// account for what is still half-received, so a crowd of slow senders can't fill the server's memory
		const now = (this.frag ? this.frag.size : 0) + this.buf.length;
		pendingTotal += now - this.held;
		this.held = now;
		if (now > 0 && !this.partialAt) this.partialAt = Date.now();
		if (now === 0) this.partialAt = 0;
		if (pendingTotal > MAX_PENDING) this.close(1013);
	}

	parse() {
		for (;;) {
			const b = this.buf;
			if (b.length < 2) return;
			const fin = (b[0] & 0x80) !== 0, op = b[0] & 0x0f, masked = (b[1] & 0x80) !== 0;
			let len = b[1] & 0x7f, off = 2;
			if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
			else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
			const cap = this.room && (this.role === "host" || this.admitted) ? MAX_BIN : MAX_FRAME;   // big packets only inside a room
			if (len > cap || !masked) { this.close(1009); return; }       // clients must mask; keep frames small
			if (b.length < off + 4 + len) return;
			const mask = b.subarray(off, off + 4);
			const payload = Buffer.from(b.subarray(off + 4, off + 4 + len));
			for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
			this.buf = b.subarray(off + 4 + len);
			if (op === 0x8) { this.close(1000); return; }
			if (op === 0x9) { this.sendFrame(0xA, payload); continue; }
			if (op === 0xA) { this.pongAt = Date.now(); continue; }
			if (op === 0x1 || op === 0x2) { this.frag = { op, parts: [payload], size: payload.length }; }
			else if (op === 0x0 && this.frag) { this.frag.parts.push(payload); this.frag.size += payload.length; }
			else continue;
			if (this.frag.size > (this.frag.op === 0x1 ? MAX_FRAME : (this.room ? MAX_BIN : MAX_FRAME))) { this.close(1009); return; }   // endless continuation frames
			if (fin) {
				const whole = Buffer.concat(this.frag.parts);
				const isText = this.frag.op === 0x1;
				this.frag = null;
				if (isText) onMessage(this, whole.toString("utf8"));
				else relay(this, whole);
			}
		}
	}

	onClose() {
		if (this._closed) return;
		this._closed = true;
		this.alive = false;
		clients.delete(this);
		pendingTotal -= this.held;
		this.held = 0;
		this.buf = Buffer.alloc(0);
		this.frag = null;
		const n = (perIp.get(this.ip) || 1) - 1;
		if (n > 0) perIp.set(this.ip, n); else perIp.delete(this.ip);
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

function rateOk(ip, map = attempts, limit = JOIN_PER_MIN) {
	const now = Date.now();
	const list = (map.get(ip) || []).filter((t) => now - t < 60000);
	list.push(now);
	map.set(ip, list);
	return list.length <= limit;
}

function roomsOf(ip) {
	let n = 0;
	for (const r of rooms.values()) if (r.ip === ip) n++;
	return n;
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
			if (room.host) room.host.send(c.admitted ? { t: "peer_leave", id: c.id } : { t: "knock_gone", id: c.id });
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
		case "admit": return doAdmit(c, m);
		case "leave": return c.close(1000);
		default: return c.send({ t: "error", code: "bad" });
	}
}

function doHost(c, m) {
	if (c.room) return c.send({ t: "error", code: "bad" });
	const ver = parseInt(m.ver, 10) || 0;
	let room = null;
	const want = typeof m.code === "string" ? m.code.toUpperCase() : "";
	const old = want ? rooms.get(want) : null;
	// taking a dropped room back (the host napped / reconnected) needs the secret token that room was given
	if (old && !old.host && typeof m.token === "string" && m.token.length === old.token.length &&
			crypto.timingSafeEqual(Buffer.from(m.token), Buffer.from(old.token))) {
		room = old;
		room.ver = ver;
	} else {
		if (!rateOk(c.ip, hostings, HOST_PER_MIN) || roomsOf(c.ip) >= ROOMS_PER_IP) return c.send({ t: "error", code: "rate" });
		if (rooms.size >= MAX_ROOMS) return c.send({ t: "error", code: "busy" });
		const code = newCode();
		if (!code) return c.send({ t: "error", code: "busy" });
		room = { code, ver, ip: c.ip, approve: false, host: null, guests: new Map(), hostName: "", dropAt: 0, token: crypto.randomBytes(18).toString("base64url") };
		rooms.set(code, room);
	}
	room.approve = m.approve === true;               // newer rooms ask the host before anyone comes in
	room.host = c;
	room.dropAt = 0;
	room.hostName = cleanName(m.name);
	c.role = "host"; c.room = room; c.id = 1; c.name = room.hostName;
	c.send({ t: "hosted", code: room.code, id: 1, max: MAX_PLAYERS, token: room.token, ice: iceFor(1) });
	for (const g of room.guests.values()) {                       // guests that waited for the host: tell the host about them again
		if (!room.approve) g.admitted = true;
		c.send(g.admitted ? { t: "peer_join", id: g.id, name: g.name } : { t: "knock", id: g.id, name: g.name });
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
	c.admitted = !room.approve;
	room.guests.set(id, c);
	if (!c.admitted) {
		// the host decides first: nothing but this knock reaches them, and no relay logins or handshakes go out yet
		c.send({ t: "waiting", id, host_name: room.hostName, code });
		room.host.send({ t: "knock", id, name: c.name });
		return;
	}
	welcome(room, c);
}

function welcome(room, c) {
	const peers = [{ id: 1, name: room.hostName }];
	for (const g of room.guests.values()) if (g !== c && g.admitted) peers.push({ id: g.id, name: g.name });
	c.send({ t: "joined", id: c.id, host_name: room.hostName, peers, code: room.code, ice: iceFor(c.id) });
	room.host.send({ t: "peer_join", id: c.id, name: c.name });
}

function doAdmit(c, m) {
	if (c.role !== "host" || !c.room) return;
	const g = c.room.guests.get(parseInt(m.id, 10));
	if (!g || g.admitted) return;
	g.admitted = true;
	welcome(c.room, g);
}

function doSig(c, m) {
	const room = c.room;
	if (!room || typeof m.data !== "object" || m.data === null) return;
	const to = parseInt(m.to, 10);
	if (c.role === "host") {
		const g = room.guests.get(to);
		if (g && g.admitted) g.send({ t: "sig", from: 1, data: m.data });
	} else if (c.role === "guest" && c.admitted && to === 1 && room.host) {      // guests only talk to the host (star shape)
		room.host.send({ t: "sig", from: c.id, data: m.data });
	}
}

// a game packet for a player whose direct link didn't come up
function relay(c, data) {
	const room = c.room;
	if (!room || data.length < 2) return;
	const now = Date.now();
	c.budget = Math.min(RELAY_BPS, c.budget + (now - c.budgetAt) * RELAY_BPS / 1000);
	c.budgetAt = now;
	if (c.budget < data.length) return;                         // over the speed limit: dropped
	c.budget -= data.length;
	const to = data[0];
	let target = null;
	if (c.role === "host") target = room.guests.get(to) || null;
	else if (c.role === "guest" && c.admitted && to === 1) target = room.host;   // guests only talk to the host (star shape)
	if (target && target.role === "guest" && !target.admitted) target = null;
	if (!target || !target.alive || target.socket.writableLength > RELAY_BACKLOG) return;
	data[0] = c.id;                                              // the receiver learns who really sent it
	target.sendFrame(0x2, data);
}

function doKick(c, m) {
	if (c.role !== "host" || !c.room) return;
	const g = c.room.guests.get(parseInt(m.id, 10));
	if (g) {
		g.send({ t: "kicked" });
		leave(g);                                          // out of the room now; the line itself closes a moment later
		setTimeout(() => g.close(1000), 300);              // (so "kicked" arrives before the close, not with it)
	}
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
	const fwd = TRUST_PROXY ? String(req.headers["x-forwarded-for"] || "").split(",")[0].trim() : "";
	const ip = fwd || String(req.socket.remoteAddress || "");
	if (clients.size >= MAX_CONNS || (perIp.get(ip) || 0) >= MAX_CONNS_PER_IP) { socket.destroy(); return; }
	new Client(socket, ip);
});

setInterval(() => {            // keepalive + clean up rooms whose host never came back
	const now = Date.now();
	for (const c of clients) {
		if (now - c.pongAt > IDLE_MS) { c.close(1001); continue; }
		if (c.partialAt && now - c.partialAt > PARTIAL_MS) { c.close(1008); continue; }
		if (now - c.pongAt > IDLE_MS / 2) c.sendFrame(0x9, Buffer.alloc(0));
	}
	for (const [code, room] of rooms) {
		if (!room.host && room.dropAt && now - room.dropAt > GRACE_MS) {
			for (const g of room.guests.values()) { g.send({ t: "closed" }); g.close(1000); }
			rooms.delete(code);
		}
	}
	for (const map of [attempts, hostings]) {
		for (const [ip, list] of map) {
			const keep = list.filter((t) => now - t < 60000);
			if (keep.length) map.set(ip, keep); else map.delete(ip);
		}
	}
}, 5000).unref();

module.exports = { server, rooms };
if (require.main === module) {
	// behind Caddy (TRUST_PROXY=1) only the proxy on this machine may connect: nobody can reach the port directly and
	// fake the forwarded address to dodge the per-address limits
	const bind = process.env.BIND || (TRUST_PROXY ? "127.0.0.1" : undefined);
	server.listen(PORT, bind, () => console.log("Lofi Room matchmaking server on " + (bind || "*") + ":" + PORT));
}
