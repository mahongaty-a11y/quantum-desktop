# Quantum Desktop

A custom GPU desktop image: **KDE Plasma + xrdp + noVNC + Cloudflare Tunnel**, built for RunPod / Vast.ai containers (no systemd required).

## What's inside

| Component | Purpose |
|---|---|
| Ubuntu 22.04 + CUDA 12.4 | GPU-ready base |
| KDE Plasma | Modern desktop (not dated XFCE) |
| xrdp + xorgxrdp | RDP on port 3389 |
| Xvfb + x11vnc + noVNC | Browser desktop on port 6080 |
| cloudflared | Auto-tunnel so you can reach it from anywhere |
| Firefox, Konsole, Dolphin | Ready to use |

## Build it (no Docker needed locally)

1. Create a GitHub repo and push this folder to it.
2. GitHub Actions builds automatically on every push.
3. Image appears at:
   ```
   ghcr.io/<your-github-username>/quantum-desktop:latest
   ```

Watch progress under the **Actions** tab of your repo.

### Make the package public

After the first build:
1. Go to your GitHub profile → **Packages** → `quantum-desktop`
2. **Package settings** → **Change visibility** → **Public**

RunPod needs to pull it without credentials.

## Use it on RunPod

In your pod config:

| Field | Value |
|---|---|
| Container image | `ghcr.io/<your-username>/quantum-desktop:latest` |
| Expose ports | `3389/tcp`, `6080/tcp`, `22/tcp` |
| Environment | `DESKTOP_USER=rdpuser` |
| Environment | `DESKTOP_PASS=<your password>` |

## Connect

**RDP:**
```
mstsc /v:<pod-ip>:3389
```
Username: `rdpuser` · Password: whatever you set in `DESKTOP_PASS`

**Browser desktop:**
```
http://<pod-ip>:6080
```
No password needed — the VNC server runs with `-nopw` for simplicity. **Change this before exposing publicly.**

## Security notes

- `x11vnc -nopw` means the browser desktop has **no password**. Only safe behind a tunnel or private network.
- Set a strong `DESKTOP_PASS`.
- The image runs as root inside the container — normal for RunPod, but don't expose port 22 publicly without key-only auth.

## Customising

**Switch desktop to XFCE (much smaller, ~1.5 GB less):**

In `Dockerfile`, replace:
```
kde-plasma-desktop konsole dolphin
```
with:
```
xfce4 xfce4-terminal thunar
```
And in `entrypoint.sh` + `Dockerfile`, replace `startplasma-x11` with `startxfce4`.

**Add your own tools:** append to the `apt-get install` list.

**Change resolution:** edit `Xvfb :1 -screen 0 1600x900x24` in `entrypoint.sh`.

## Why this beats a startup script

| Startup script | Prebuilt image |
|---|---|
| Installs packages every boot (~5 min) | Boots in seconds |
| Breaks when a repo changes | Frozen, reproducible |
| `systemctl` fails in containers | Direct daemon starts |
| Hard to debug | Build logs show every step |
