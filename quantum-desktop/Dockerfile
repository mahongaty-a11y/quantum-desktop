# ============================================================
#  Quantum Desktop — custom GPU desktop image
#  KDE Plasma + xrdp + noVNC + Cloudflare Tunnel
#  Built for RunPod / Vast.ai GPU pods (no systemd)
# ============================================================
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8

# ---------- base packages ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg sudo dbus dbus-x11 \
      xrdp xorgxrdp \
      x11vnc xvfb xterm \
      novnc websockify \
      kde-plasma-desktop konsole dolphin \
      firefox \
    && rm -rf /var/lib/apt/lists/*

# ---------- cloudflared (tunnel for browser access) ----------
RUN wget -qO /usr/local/bin/cloudflared \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

# ---------- desktop user ----------
ARG DESKTOP_USER=rdpuser
ARG DESKTOP_PASS=changeme
RUN useradd -m -s /bin/bash ${DESKTOP_USER} \
    && echo "${DESKTOP_USER}:${DESKTOP_PASS}" | chpasswd \
    && usermod -aG sudo ${DESKTOP_USER} \
    && echo "${DESKTOP_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ---------- session files ----------
RUN echo "startplasma-x11" > /home/${DESKTOP_USER}/.xsession \
    && chmod +x /home/${DESKTOP_USER}/.xsession \
    && chown ${DESKTOP_USER}:${DESKTOP_USER} /home/${DESKTOP_USER}/.xsession \
    && echo "startplasma-x11" > /root/.xsession \
    && chmod +x /root/.xsession

# ---------- xrdp config ----------
RUN sed -i 's/^port=3389/port=3389/' /etc/xrdp/xrdp.ini \
    && sed -i 's/^max_bpp=32/max_bpp=24/' /etc/xrdp/xrdp.ini \
    && sed -i 's/^security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini \
    && mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp \
    && chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp

# ---------- noVNC ----------
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# ---------- entrypoint ----------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389 6080 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
