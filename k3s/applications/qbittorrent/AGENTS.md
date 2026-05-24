# qBittorrent K3s Application

qBittorrent running in K3s with Gluetun WireGuard VPN sidecar, replacing the Docker-based
Transmission deployment.

## Architecture

```
qbittorrent namespace
├── gluetun          (VPN sidecar — NordVPN WireGuard)
├── qbittorrent      (lscr.io/linuxserver/qbittorrent:5.0.4)
├── qbt-exporter     (ghcr.io/esanchezm/prometheus-qbittorrent-exporter:v1.3.0)
└── gluetun-exporter (ghcr.io/crstian19/gluetun-exporter:latest)
```

## Storage / Directory Layout

| Mount | PVC | NAS path | Purpose |
|-------|-----|----------|---------|
| `/config` | qbittorrent-config (5Gi local-path) | node local | qBittorrent config DB |
| `/gluetun` | gluetun-config (1Gi local-path) | node local | Gluetun config |
| `/data` | qbittorrent-media (10Ti smb-media) | `//192.168.1.20/data` = NAS `/volume1/data` | All media + downloads |

qBittorrent downloads go to `/data/torrents/`. The NAS directory layout:

```
/volume1/data/
├── torrents/       ← qBittorrent save path (set in WebUI)
│   ├── movies/     ← category path for movies
│   └── tv/         ← category path for TV
├── movies/         ← Radarr library root
└── tv/             ← Sonarr library root
```

**TRaSH Guides alignment**: This matches the recommended single-volume layout where the
download client and *arr apps share the same root (`/data`).

## *arr Download Client Integration

After adding qBittorrent as a download client in Radarr/Sonarr:

- **Host**: `qbittorrent.qbittorrent.svc.cluster.local`
- **Port**: `8080`
- **Category (movies)**: `movies` — sets save path to `/data/torrents/movies/`
- **Category (tv)**: `tv` — sets save path to `/data/torrents/tv/`

### Radarr/Sonarr Mount Path Migration

The radarr and sonarr deployments were updated to mount the NAS SMB share at `/data`
(previously `/data/media`). After applying these changes:

1. Update **Root Folder** in Radarr UI: `Settings → Media Management`
   - Remove `/data/media/movies`, add `/data/movies`
2. Update **Root Folder** in Sonarr UI: `Settings → Media Management`
   - Remove `/data/media/tv`, add `/data/tv`

The actual NAS paths are unchanged — only the container mount point changed.

## SOPS Secrets Required

Before Flux can reconcile this app, two encrypted secrets must exist:

### 1. nordvpn-credentials

```bash
cp nordvpn-credentials.sops.yaml.example nordvpn-credentials.sops.yaml
# Edit: set wireguard-private-key
SOPS_AGE_KEY_FILE=~/.kube/k3s-homelab-age.agekey sops --encrypt --in-place nordvpn-credentials.sops.yaml
```

> **Note**: The `nordvpn-credentials` secret uses the same WireGuard key as sabnzbd.
> You may reuse the same key value, but the secret must exist in the `qbittorrent` namespace.

### 2. qbittorrent-credentials

```bash
cp qbittorrent-credentials.sops.yaml.example qbittorrent-credentials.sops.yaml
# Edit: set username and password to match qBittorrent WebUI credentials
SOPS_AGE_KEY_FILE=~/.kube/k3s-homelab-age.agekey sops --encrypt --in-place qbittorrent-credentials.sops.yaml
```

Set matching credentials in qBittorrent WebUI: `Tools → Options → Web UI → Authentication`.

## Ingress

- URL: `https://qbittorrent.homelab.properties`
- TLS: cert-manager letsencrypt-prod

## Ports

| Port | Name | Purpose |
|------|------|---------|
| 8080 | http | qBittorrent WebUI |
| 6881 | bittorrent | BitTorrent TCP traffic (through VPN) |
| 9090 | qbt-metrics | prometheus-qbittorrent-exporter metrics |
| 9586 | gluetun-metrics | gluetun-exporter metrics |
