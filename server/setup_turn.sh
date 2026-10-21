#!/bin/bash
# Adds a relay (TURN) to the room server, for players whose internet blocks a direct link.
# Run on the droplet as root:  curl -fsSL https://raw.githubusercontent.com/Ozyman515/lofi-room/main/server/setup_turn.sh | bash
set -e
HOST=lofirooms.duckdns.org
REPO=https://raw.githubusercontent.com/Ozyman515/lofi-room/main

echo "== installing the relay (coturn)"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq coturn openssl curl

# one secret shared by the relay and the room server; kept if this script runs again
if [ -f /etc/lofi-turn.secret ]; then SECRET=$(cat /etc/lofi-turn.secret); else SECRET=$(openssl rand -hex 24); echo "$SECRET" > /etc/lofi-turn.secret; chmod 600 /etc/lofi-turn.secret; fi

echo "== writing /etc/turnserver.conf"
cat > /etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$SECRET
realm=$HOST
min-port=49160
max-port=49200
user-quota=8
total-quota=40
no-cli
no-tls
no-dtls
no-multicast-peers
no-loopback-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
log-file=syslog
EOF
[ -f /etc/default/coturn ] && sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn

echo "== opening the firewall"
ufw allow 3478 >/dev/null
ufw allow 49160:49200/udp >/dev/null

echo "== updating the room server"
curl -fsSL "$REPO/server/server.js" -o /opt/lofi-rooms/server.js.new
mv /opt/lofi-rooms/server.js.new /opt/lofi-rooms/server.js
mkdir -p /etc/systemd/system/lofi-rooms.service.d
printf '[Service]\nEnvironment=TURN_SECRET=%s\nEnvironment=TURN_HOST=%s\n' "$SECRET" "$HOST" > /etc/systemd/system/lofi-rooms.service.d/turn.conf
chmod 600 /etc/systemd/system/lofi-rooms.service.d/turn.conf

systemctl daemon-reload
systemctl enable coturn >/dev/null 2>&1 || true
systemctl restart coturn
systemctl restart lofi-rooms
sleep 1
echo
systemctl is-active coturn lofi-rooms
curl -s http://127.0.0.1:8787/health; echo
echo "== done. Both lines above should say active, and the last one ok."
