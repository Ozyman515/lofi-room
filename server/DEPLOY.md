# Deploying the room-code server

The server only matches players by room code and passes WebRTC handshakes along. No game
traffic goes through it, so a tiny machine is enough (about 5 MB of RAM).

## Recommended: DigitalOcean $4/month droplet (Ubuntu, 512 MB)

1. Create the droplet and point a (sub)domain at its IP, e.g. `rooms.example.com`.
   A free DDNS name (DuckDNS) also works.
2. Install Node 20+: `apt install -y nodejs` (or use nodesource).
3. Copy `server.js` to `/opt/lofi-rooms/` (no npm install needed: it has no dependencies).
4. Run it as a service. `/etc/systemd/system/lofi-rooms.service`:

       [Unit]
       Description=Lofi Room code server
       After=network.target
       [Service]
       ExecStart=/usr/bin/node /opt/lofi-rooms/server.js
       Environment=PORT=8787
       Environment=TRUST_PROXY=1
       Restart=always
       User=nobody
       [Install]
       WantedBy=multi-user.target

   then `systemctl enable --now lofi-rooms`.
5. HTTPS in front (the Quest needs `wss://`). Install Caddy and use this Caddyfile:

       rooms.example.com {
           reverse_proxy 127.0.0.1:8787
       }

6. In the room, set the server address: in `user://lofi_room.cfg`

       [net]
       server="wss://rooms.example.com"

   or the environment variable `LOFI_SERVER`. Change `DEFAULT_SERVER` in `net_config.gd`
   before shipping so players need no setup.

## Free options
- Oracle Cloud "Always Free" VM: same steps, but signup can be picky.
- Render / Fly free tiers: work, but idle servers sleep, so the first room can take ~30 s to open.

## Players behind strict NATs (about 1 in 10)
Direct connections use free Cloudflare STUN. A TURN relay covers the rest: Cloudflare TURN is free for
the first 1,000 GB a month, then $0.05/GB. Put its details in the config:

    [net]
    turn_url="turn:turn.cloudflare.com:3478"
    turn_user="..."
    turn_pass="..."

## Settings (environment variables)
`PORT` (8787), `MAX_PLAYERS` (4), `GRACE_MS` (90000: how long a host can come back to the same code),
`JOIN_PER_MIN` (12 join tries per IP per minute), `HOST_PER_MIN` (6 rooms opened per IP per minute),
`ROOMS_PER_IP` (3 rooms open at once per IP), `MAX_ROOMS` (2000), `MAX_CONNS` (400), `MAX_CONNS_PER_IP` (8),
`MAX_PENDING` (96 MB of half-received messages across everyone; past that, the sender is dropped),
`TRUST_PROXY` (set to 1 only behind Caddy/nginx, so the real client address is used for the per-address
limits; with it set the server listens on 127.0.0.1 only, so nobody can reach it around the proxy),
`BIND` (override the listen address). Test with `node test.js`.

Rooms opened by the room (version 104 on) ask the host before anyone comes in: the guest waits, the host
gets a "knock" and lets them in ("admit") or turns them away ("kick"). A guest that hasn't been let in gets
no relay login, no handshakes, and can't send big packets.

## What the server knows and keeps
Nothing is stored on disk. In memory, per connection: the address, the display name, the room code, the
game version. Game traffic (poses, inputs, pictures, comic pages) never passes through it; players talk
to each other directly over encrypted WebRTC. Players therefore see each other's addresses, like any
peer-to-peer game.

## Updating the server later
On the droplet:

    curl -fsSL https://raw.githubusercontent.com/Ozyman515/lofi-room/main/server/server.js -o /opt/lofi-rooms/server.js && systemctl restart lofi-rooms && curl -s http://127.0.0.1:8787/health

## When players can't link directly
The room first tries a direct link (WebRTC, with the TURN relay from `setup_turn.sh` if installed). If nothing
connects within 7 seconds, game packets go through this server over the same secure websocket instead
(capped at RELAY_BPS bytes a second per player, 4 MB/s by default). Each PC writes what happened to `net.log`
in its save folder (%APPDATA%\Godot\app_userdata\Lofi Room on Windows).
