#!/bin/bash
DESKTOP_USER="${DESKTOP_USER:-rdpuser}"
DESKTOP_PASS="${DESKTOP_PASS:-changeme}"
log() { echo "[entrypoint] $*"; }

log "starting"

# ---------- users ----------
id "$DESKTOP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DESKTOP_USER" 2>/dev/null
echo "$DESKTOP_USER:$DESKTOP_PASS" | chpasswd 2>/dev/null
echo "root:$DESKTOP_PASS" | chpasswd 2>/dev/null
usermod -aG sudo "$DESKTOP_USER" 2>/dev/null
usermod -U "$DESKTOP_USER" 2>/dev/null
usermod -U root 2>/dev/null

# ---------- session binary ----------
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

# ---------- xrdp runtime dirs ----------
mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp /tmp/.X11-unix 2>/dev/null
chmod 1777 /tmp/.X11-unix 2>/dev/null
chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp 2>/dev/null
rm -f /tmp/.X0-lock /tmp/.X10-lock /tmp/.X11-unix/X0 /tmp/.X11-unix/X10 2>/dev/null

# ---------- xrdp (uses its own display, does NOT need Xvfb) ----------
log "starting xrdp-sesman"
/usr/sbin/xrdp-sesman 2>&1 | head -3
sleep 2
log "starting xrdp"
/usr/sbin/xrdp 2>&1 | head -3
sleep 3

if grep -qi ':0D05' /proc/net/tcp 2>/dev/null; then
  log "xrdp LISTENING on 3389"
else
  log "WARN xrdp not listening - retrying"
  pkill xrdp 2>/dev/null; sleep 1
  /usr/sbin/xrdp 2>&1 | head -3
  sleep 2
fi

# ---------- browser desktop on :1 ----------
log "starting Xvfb :1"
Xvfb :1 -screen 0 1600x900x24 >/tmp/xvfb.log 2>&1 &
sleep 5

if [ -n "$SESSION" ]; then
  log "starting $SESSION on :1"
  su "$DESKTOP_USER" -c "DISPLAY=:1 $SESSION" >/tmp/session.log 2>&1 &
  sleep 5
fi

# ---------- x11vnc with retry (it segfaults on first attempt) ----------
start_vnc() {
  pkill x11vnc 2>/dev/null
  sleep 1
  x11vnc -display :1 -forever -shared -nopw -rfbport 5900 \
         -noxdamage -nolookup -bg >/tmp/x11vnc.log 2>&1
  sleep 3
  grep -qi ':170C' /proc/net/tcp 2>/dev/null
}

log "starting x11vnc"
if start_vnc; then
  log "x11vnc LISTENING on 5900"
else
  log "x11vnc retry"
  sleep 3
  if start_vnc; then log "x11vnc LISTENING on 5900"; else log "WARN x11vnc failed"; fi
fi

# ---------- websockify ----------
log "starting websockify"
pkill websockify 2>/dev/null
sleep 1
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 3

log "READY - RDP 3389 | browser 6080 | both can run together"
exec tail -f /dev/null
