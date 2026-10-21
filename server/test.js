// End-to-end check of the matchmaking server: node test.js
"use strict";
const assert = require("assert");
process.env.PORT = "0";
const { server, rooms } = require("./server.js");

function open(port) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket("ws://127.0.0.1:" + port);
		const q = []; let waiter = null;
		ws.binaryType = "arraybuffer";
		ws.onmessage = (e) => { const m = typeof e.data === "string" ? JSON.parse(e.data) : { bin: [...new Uint8Array(e.data)] }; if (waiter) { const w = waiter; waiter = null; w(m); } else q.push(m); };
		ws.onopen = () => resolve({ ws,
			send: (o) => ws.send(JSON.stringify(o)),
			next: () => new Promise((r, rej) => { if (q.length) return r(q.shift()); waiter = r; setTimeout(() => rej(new Error("timeout")), 2000); }),
			closed: () => new Promise((r) => { ws.onclose = r; }),
		});
		ws.onerror = reject;
	});
}

(async () => {
	await new Promise((r) => server.listen(0, r));
	const port = server.address().port;
	const host = await open(port);
	host.send({ t: "host", ver: 68, name: "Host" });
	const hosted = await host.next();
	assert.strictEqual(hosted.t, "hosted"); assert.match(hosted.code, /^[A-HJ-NP-Z2-9]{6}$/);
	const code = hosted.code;

	const g1 = await open(port);
	g1.send({ t: "join", code: code.toLowerCase(), ver: 68, name: "Guest <b>1</b>" });
	const j1 = await g1.next();
	assert.strictEqual(j1.t, "joined"); assert.strictEqual(j1.id, 2); assert.strictEqual(j1.host_name, "Host");
	const pj = await host.next(); assert.deepStrictEqual([pj.t, pj.id, pj.name], ["peer_join", 2, "Guest b1b"]);

	// signalling goes both ways, host -> guest 2 and back
	host.send({ t: "sig", to: 2, data: { sdp: "offer" } });
	assert.deepStrictEqual(await g1.next(), { t: "sig", from: 1, data: { sdp: "offer" } });
	g1.send({ t: "sig", to: 1, data: { sdp: "answer" } });
	assert.deepStrictEqual(await host.next(), { t: "sig", from: 2, data: { sdp: "answer" } });

	// wrong code, wrong version
	const gx = await open(port);
	gx.send({ t: "join", code: "ZZZZZZ", ver: 68, name: "x" });
	assert.strictEqual((await gx.next()).code, "no_room");
	gx.send({ t: "join", code, ver: 67, name: "x" });
	const ve = await gx.next(); assert.deepStrictEqual([ve.code, ve.host_ver], ["version", 68]);

	// fill the room (host + 3 guests), the next one is refused
	const g2 = await open(port); g2.send({ t: "join", code, ver: 68, name: "G2" }); assert.strictEqual((await g2.next()).id, 3);
	const g3 = await open(port); g3.send({ t: "join", code, ver: 68, name: "G3" }); assert.strictEqual((await g3.next()).id, 4);
	gx.send({ t: "join", code, ver: 68, name: "late" });
	assert.strictEqual((await gx.next()).code, "full");
	await host.next(); await host.next();       // peer_join for 3 and 4

	// a guest can't talk to another guest
	g2.send({ t: "sig", to: 4, data: { sneaky: true } });
	g1.send({ t: "ping" }); assert.strictEqual((await g1.next()).t, "pong");

	// relayed game packets: host -> guest and guest -> host carry the real sender; guest -> guest is refused
	host.ws.send(new Uint8Array([3, 5, 9, 9]));
	assert.deepStrictEqual((await g2.next()).bin, [1, 5, 9, 9]);
	g2.ws.send(new Uint8Array([1, 6, 7]));
	assert.deepStrictEqual((await host.next()).bin, [3, 6, 7]);
	g2.ws.send(new Uint8Array([2, 6, 7]));
	g1.send({ t: "ping" }); assert.strictEqual((await g1.next()).t, "pong");   // nothing binary reached guest 2's neighbour

	// kick
	host.send({ t: "kick", id: 4 });
	assert.strictEqual((await g3.next()).t, "kicked");
	const pl = await host.next(); assert.deepStrictEqual([pl.t, pl.id], ["peer_leave", 4]);

	// the host drops: guests are told, the host can take the code back
	host.ws.close();
	assert.strictEqual((await g1.next()).t, "host_away");
	assert.strictEqual((await g2.next()).t, "host_away");
	const host2 = await open(port);
	// an impostor who knows the code can't take the room; the real host's token can
	const bad = await open(port); bad.send({ t: "host", ver: 68, name: "Imp", code });
	const badres = await bad.next(); assert.notStrictEqual(badres.code, code); bad.send({ t: "leave" });
	host2.send({ t: "host", ver: 68, name: "Host", code, token: hosted.token });
	assert.strictEqual((await host2.next()).code, code);
	const again = [await host2.next(), await host2.next()].map((m) => m.id).sort();
	assert.deepStrictEqual(again, [2, 3]);
	assert.strictEqual((await g1.next()).t, "host_back");

	// join attempts are rate limited per address
	let limited = false;
	for (let i = 0; i < 20 && !limited; i++) { gx.send({ t: "join", code: "AAAAAA", ver: 68, name: "x" }); limited = (await gx.next()).code === "rate"; }
	assert.ok(limited);

	console.log("server tests passed, rooms:", rooms.size);
	process.exit(0);
})().catch((e) => { console.error("FAILED", e); process.exit(1); });
