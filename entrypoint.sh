#!/bin/bash
DESKTOP_USER="${DESKTOP_USER:-rdpuser}"
DESKTOP_PASS="${DESKTOP_PASS:-changeme}"
INSTANCE_ID="${INSTANCE_ID:-}"
log() { echo "[entrypoint] $*"; }

log "starting"

id "$DESKTOP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DESKTOP_USER" 2>/dev/null
echo "$DESKTOP_USER:$DESKTOP_PASS" | chpasswd 2>/dev/null
echo "root:$DESKTOP_PASS" | chpasswd 2>/dev/null
usermod -aG sudo "$DESKTOP_USER" 2>/dev/null
usermod -U "$DESKTOP_USER" 2>/dev/null
usermod -U root 2>/dev/null

SESSION=""
for s in startplasma-x11 startkde startxfce4 xfce4-session; do
  if command -v "$s" >/dev/null 2>&1; then SESSION="$s"; break; fi
done
log "session binary: ${SESSION:-NONE}"

if [ -n "$SESSION" ]; then
  echo "$SESSION" > "/home/$DESKTOP_USER/.xsession" 2>/dev/null
  chmod +x "/home/$DESKTOP_USER/.xsession" 2>/dev/null
  chown "$DESKTOP_USER:$DESKTOP_USER" "/home/$DESKTOP_USER/.xsession" 2>/dev/null
  echo "$SESSION" > /root/.xsession 2>/dev/null
  chmod +x /root/.xsession 2>/dev/null
fi

mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp /tmp/.X11-unix 2>/dev/null
chmod 1777 /tmp/.X11-unix 2>/dev/null
chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp 2>/dev/null
rm -f /tmp/.X0-lock /tmp/.X10-lock /tmp/.X11-unix/X0 /tmp/.X11-unix/X10 2>/dev/null

log "starting xrdp-sesman"
/usr/sbin/xrdp-sesman 2>&1 | head -3
sleep 2
log "starting xrdp"
/usr/sbin/xrdp 2>&1 | head -3
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

start_vnc() {
  pkill x11vnc 2>/dev/null
  sleep 1
  x11vnc -display :1 -forever -shared -nopw -rfbport 5900 -noxdamage -nolookup -bg >/tmp/x11vnc.log 2>&1
  sleep 3
  grep -qi ':170C' /proc/net/tcp 2>/dev/null
}
log "starting x11vnc"
if start_vnc; then log "x11vnc LISTENING 5900"; else sleep 3; start_vnc && log "x11vnc LISTENING 5900" || log "WARN x11vnc failed"; fi

log "starting websockify"
pkill websockify 2>/dev/null
sleep 1
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 3

# ---------- Cloudflare Tunnel: trusted HTTPS URL ----------
if command -v cloudflared >/dev/null 2>&1; then
  log "starting cloudflared tunnel"
  cloudflared tunnel --url http://localhost:6080 --no-autoupdate >/tmp/cf.log 2>&1 &
  for i in $(seq 1 20); do
    sleep 3
    URL=$(grep -o 'https://[a-z0-9-]*[.]trycloudflare[.]com' /tmp/cf.log 2>/dev/null | head -1)
    [ -n "$URL" ] && break
  done
  if [ -n "$URL" ]; then
    log "TUNNEL URL: $URL"
    if [ -n "$INSTANCE_ID" ]; then
      curl -s -X POST "https://cloud.tymessenger.app/api/instances/$INSTANCE_ID/tunnel" \
        -H "Content-Type: application/json" -d "{\"url\":\"$URL\"}" >/dev/null 2>&1 || true
      log "tunnel URL reported to dashboard"
    fi
  else
    log "WARN no tunnel URL yet - check /tmp/cf.log"
  fi
fi

log "READY - RDP 3389 | browser 6080 | tunnel https"
exec tail -f /dev/null
