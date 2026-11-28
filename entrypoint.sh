#!/bin/bash
set -uo pipefail

DESKTOP_USER="${DESKTOP_USER:-rdpuser}"
INSTANCE_ID="${INSTANCE_ID:-}"
REPORT_TOKEN="${REPORT_TOKEN:-}"
log() { echo "[entrypoint] $*"; }

if [ -z "${DESKTOP_PASS:-}" ]; then
  log "FATAL: DESKTOP_PASS is not set - refusing to start with a default password"
  exit 1
fi

log "starting"

id "$DESKTOP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DESKTOP_USER" 2>/dev/null
echo "$DESKTOP_USER:$DESKTOP_PASS" | chpasswd 2>/dev/null
usermod -aG sudo "$DESKTOP_USER" 2>/dev/null

# root stays locked: no password login, ever
passwd -l root >/dev/null 2>&1

SESSION=""
for s in startplasma-x11 startkde startxfce4 xfce4-session; do
  if command -v "$s" >/dev/null 2>&1; then SESSION="$s"; break; fi
done
log "session binary: ${SESSION:-NONE}"

if [ -n "$SESSION" ]; then
  echo "$SESSION" > "/home/$DESKTOP_USER/.xsession" 2>/dev/null
  chmod +x "/home/$DESKTOP_USER/.xsession" 2>/dev/null
  chown "$DESKTOP_USER:$DESKTOP_USER" "/home/$DESKTOP_USER/.xsession" 2>/dev/null
fi

mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp /tmp/.X11-unix 2>/dev/null
chmod 1777 /tmp/.X11-unix 2>/dev/null
chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp 2>/dev/null
rm -f /tmp/.X0-lock /tmp/.X10-lock /tmp/.X11-unix/X0 /tmp/.X11-unix/X10 2>/dev/null

log "starting xrdp-sesman"
/usr/sbin/xrdp-sesman >/tmp/sesman.log 2>&1
sleep 2
log "starting xrdp"
/usr/sbin/xrdp >/tmp/xrdp.log 2>&1
sleep 3
grep -qi ':0D05' /proc/net/tcp 2>/dev/null && log "xrdp LISTENING 3389" || log "WARN xrdp not listening"

log "starting Xvfb :1"
Xvfb :1 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 5

if [ -n "$SESSION" ]; then
  log "starting $SESSION on :1"
  su "$DESKTOP_USER" -c "DISPLAY=:1 $SESSION" >/tmp/session.log 2>&1 &
  sleep 5
fi

# ---- VNC: password required, loopback only ----
x11vnc -storepasswd "$DESKTOP_PASS" /etc/x11vnc.pass >/dev/null 2>&1

start_vnc() {
  pkill x11vnc 2>/dev/null
  sleep 1
  x11vnc -display :1 -localhost -rfbauth /etc/x11vnc.pass \
         -forever -shared -rfbport 5900 -noxdamage -nolookup -bg \
         >/tmp/x11vnc.log 2>&1
  sleep 3
  grep -qi ':170C' /proc/net/tcp 2>/dev/null
}
log "starting x11vnc (password required, loopback only)"
if start_vnc; then
  log "x11vnc LISTENING 127.0.0.1:5900"
else
  sleep 3
  start_vnc && log "x11vnc LISTENING 127.0.0.1:5900" || log "WARN x11vnc failed - see /tmp/x11vnc.log"
fi

log "starting websockify"
pkill websockify 2>/dev/null
sleep 1
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 3

# ---- Cloudflare Tunnel ----
if command -v cloudflared >/dev/null 2>&1; then
  log "starting cloudflared tunnel"
  cloudflared tunnel --url http://localhost:6080 --no-autoupdate >/tmp/cf.log 2>&1 &
  URL=""
  for i in $(seq 1 20); do
    sleep 3
    URL=$(grep -o 'https://[a-z0-9-]*[.]trycloudflare[.]com' /tmp/cf.log 2>/dev/null | head -1)
    [ -n "$URL" ] && break
  done
  if [ -n "$URL" ]; then
    log "TUNNEL URL: $URL"
    log "viewer: $URL/vnc.html?autoconnect=true&path=websockify"
    if [ -n "$INSTANCE_ID" ] && [ -n "$REPORT_TOKEN" ]; then
      curl -s -X POST "https://cloud.tymessenger.app/api/instances/$INSTANCE_ID/novnc" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $REPORT_TOKEN" \
        -d "{\"url\":\"$URL/vnc.html?autoconnect=true&path=websockify\"}" \
        >/dev/null 2>&1 || true
      log "tunnel URL reported to dashboard"
    elif [ -n "$INSTANCE_ID" ]; then
      log "WARN REPORT_TOKEN not set - paste the URL into the dashboard manually"
    fi
  else
    log "WARN no tunnel URL yet - check /tmp/cf.log"
  fi
fi

log "READY - RDP 3389 (password) | browser 6080 (password) | tunnel https"
exec tail -f /dev/null
