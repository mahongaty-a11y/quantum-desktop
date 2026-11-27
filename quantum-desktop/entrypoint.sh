#!/bin/bash
# ============================================================
#  Quantum Desktop entrypoint
#  Starts xrdp + noVNC without systemd (RunPod containers)
# ============================================================
set -u

DESKTOP_USER="${DESKTOP_USER:-rdpuser}"
DESKTOP_PASS="${DESKTOP_PASS:-changeme}"
INSTANCE_ID="${INSTANCE_ID:-}"

log() { echo "[entrypoint] $*"; }

# ---------- ensure user password matches env ----------
if id "$DESKTOP_USER" >/dev/null 2>&1; then
  echo "${DESKTOP_USER}:${DESKTOP_PASS}" | chpasswd 2>/dev/null && log "password set for $DESKTOP_USER"
else
  useradd -m -s /bin/bash "$DESKTOP_USER"
  echo "${DESKTOP_USER}:${DESKTOP_PASS}" | chpasswd
  usermod -aG sudo "$DESKTOP_USER"
  log "created user $DESKTOP_USER"
fi

# ---------- session file (must be executable) ----------
echo "startplasma-x11" > "/home/${DESKTOP_USER}/.xsession"
chmod +x "/home/${DESKTOP_USER}/.xsession"
chown "${DESKTOP_USER}:${DESKTOP_USER}" "/home/${DESKTOP_USER}/.xsession"

# ---------- runtime dirs ----------
mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp 2>/dev/null || true

# ---------- clear stale locks ----------
rm -f /tmp/.X0-lock /tmp/.X10-lock /tmp/.X11-unix/X0 /tmp/.X11-unix/X10 2>/dev/null || true
pkill -u "$DESKTOP_USER" 2>/dev/null || true

# ---------- start xrdp (no systemd) ----------
pkill xrdp-sesman 2>/dev/null || true
pkill xrdp 2>/dev/null || true
sleep 1

log "starting xrdp-sesman"
/usr/sbin/xrdp-sesman
sleep 1

log "starting xrdp"
/usr/sbin/xrdp
sleep 2

if ss -tln 2>/dev/null | grep -q ':3389'; then
  log "xrdp listening on 3389"
else
  log "WARNING: xrdp not listening on 3389"
fi

# ---------- start noVNC (browser desktop) ----------
log "starting noVNC on 6080"
Xvfb :1 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 2

su "$DESKTOP_USER" -c "DISPLAY=:1 startplasma-x11" >/tmp/plasma.log 2>&1 &
sleep 3

x11vnc -display :1 -forever -shared -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
sleep 2

websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 2

# ---------- optional Cloudflare Tunnel ----------
if [ -n "$INSTANCE_ID" ]; then
  log "starting cloudflared tunnel"
  cloudflared tunnel --url http://localhost:6080 >/tmp/cf.log 2>&1 &
  sleep 15
  URL=$(grep -o 'https://[a-z0-9-]*[.]trycloudflare[.]com' /tmp/cf.log | head -1)
  if [ -n "$URL" ]; then
    log "tunnel URL: $URL"
    curl -s -X POST "https://cloud.tymessenger.app/api/instances/${INSTANCE_ID}/tunnel" \
      -H "Content-Type: application/json" \
      -d "{\"url\":\"$URL\"}" >/dev/null 2>&1 || true
  fi
fi

log "ready — RDP on 3389, browser desktop on 6080"

# ---------- keep container alive ----------
tail -f /dev/null
