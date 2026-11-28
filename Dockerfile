# Quantum Desktop - custom GPU desktop image (hardened)
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg sudo dbus dbus-x11 \
      xrdp xorgxrdp \
      x11vnc xvfb xterm \
      novnc websockify \
      plasma-desktop plasma-workspace konsole dolphin \
      firefox \
    && rm -rf /var/lib/apt/lists/*

RUN wget -qO /usr/local/bin/cloudflared \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod +x /usr/local/bin/cloudflared

ARG DESKTOP_USER=rdpuser
RUN useradd -m -s /bin/bash ${DESKTOP_USER} \
    && usermod -aG sudo ${DESKTOP_USER} \
    && passwd -l ${DESKTOP_USER}

RUN echo "startplasma-x11" > /home/${DESKTOP_USER}/.xsession \
    && chmod +x /home/${DESKTOP_USER}/.xsession \
    && chown ${DESKTOP_USER}:${DESKTOP_USER} /home/${DESKTOP_USER}/.xsession

RUN sed -i 's/^max_bpp=32/max_bpp=24/' /etc/xrdp/xrdp.ini \
    && mkdir -p /run/xrdp /var/run/xrdp /var/log/xrdp \
    && chown xrdp:xrdp /run/xrdp /var/run/xrdp /var/log/xrdp

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389 6080
ENTRYPOINT ["/bin/bash", "/usr/local/bin/entrypoint.sh"]
