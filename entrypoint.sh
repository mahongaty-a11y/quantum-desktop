#!/bin/bash
DESKTOP_USER="${DESKTOP_USER:-rdpuser}"
DESKTOP_PASS="${DESKTOP_PASS:-changeme}"
log() { echo "[entrypoint] $*"; }

log "starting"

id "$DESKTOP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DESKTOP_USER" 2>/dev/null
echo "$DESKTOP_USER:$DESKTOP_PASS" | chpasswd 2>/dev/null
echo "root:$DESKTOP_PASS" | chpasswd 2>/dev/null
usermod -aG sudo "$DESKTOP_USER" 2>/dev/null

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
/usr/sbin/xrdp-sesman 2>&1 | head -5
sleep 1
log "starting xrdp"
/usr/sbin/xrdp 2>&1 | head -5
sleep 2

log "xrdp ports:"
ss -tln 2>/dev/null | grep -E "3389|3350" || log "no xrdp ports"

log "starting Xvfb"
Xvfb :1 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 2

if [ -n "$SESSION" ]; then
  log "starting $SESSION"
  su "$DESKTOP_USER" -c "DISPLAY=:1 $SESSION" >/tmp/session.log 2>&1 &
fi
sleep 3

log "starting x11vnc"
x11vnc -display :1 -forever -shared -nopw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
sleep 2

log "starting websockify"
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 2

log "READY - rdp 3389, browser 6080"
exec tail -f /dev/null
