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
`JOIN_PER_MIN` (12 join tries per IP per minute), `MAX_ROOMS` (2000), `MAX_CONNS` (4000),
`MAX_CONNS_PER_IP` (8), `TRUST_PROXY` (set to 1 only behind Caddy/nginx, so the real client address is used
for the per-address limits; never when the server is reachable directly). Test with `node test.js`.

## What the server knows and keeps
Nothing is stored on disk. In memory, per connection: the address, the display name, the room code, the
game version. Game traffic (poses, inputs, pictures, comic pages) never passes through it; players talk
to each other directly over encrypted WebRTC. Players therefore see each other's addresses, like any
peer-to-peer game.
