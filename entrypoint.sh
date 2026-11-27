#!/bin/bash
set -u
DESKTOP_USER="${DESKTOP_USER:-rdpuser}"
DESKTOP_PASS="${DESKTOP_PASS:-changeme}"
log() { echo "[entrypoint] $*"; }

log "starting"

# user
if ! id "$DESKTOP_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$DESKTOP_USER"
fi
echo "$DESKTOP_USER:$DESKTOP_PASS" | chpasswd
usermod -aG sudo "$DESKTOP_USER" 2>/dev/null || true
echo "root:$DESKTOP_PASS" | chpasswd 2>/dev/null || true

# session file - try several session binaries
SESSION=""
for s in startplasma-x11 startkde startxfce4 xfce4-session; do
  if command -v "$s" >/dev/null 2>&1; then SESSION="$s"; break; fi
done
log "session binary: ${SESSION:-NONE}"

if [ -n "$SESSION" ]; then
  echo "$SESSION" > "/home/$DESKTOP_USER/.xsession"
  chmod +x "/home/$DESKTOP_USER/.xsession"
  chown "$DESKTOP_USER:$DESKTOP_USER" "/home/$DESKTOP_USER/.xsession"
  echo "$SESSION" > /root/.xsession
  chmod +x /root/.xsession
fi

# dirs
mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp 2>/dev/null || true
rm -f /tmp/.X0-lock /tmp/.X10-lock /tmp/.X11-unix/X0 /tmp/.X11-unix/X10 2>/dev/null || true

# xrdp
pkill xrdp-sesman 2>/dev/null || true
pkill xrdp 2>/dev/null || true
sleep 1
/usr/sbin/xrdp-sesman || log "sesman failed"
sleep 1
/usr/sbin/xrdp || log "xrdp failed"
sleep 2
log "xrdp started"

# noVNC
Xvfb :1 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 2
if [ -n "$SESSION" ]; then
  su "$DESKTOP_USER" -c "DISPLAY=:1 $SESSION" >/tmp/session.log 2>&1 &
fi
sleep 3
x11vnc -display :1 -forever -shared -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
sleep 2
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 2

log "ready - RDP 3389, browser 6080"
tail -f /dev/null
