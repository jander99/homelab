# qBittorrent K3s Application

qBittorrent running in K3s with Gluetun WireGuard VPN sidecar, replacing the Docker-based
Transmission deployment.

## Architecture

```
qbittorrent namespace
├── gluetun          (VPN sidecar — NordVPN WireGuard)
├── qbittorrent      (lscr.io/linuxserver/qbittorrent:5.0.4)
├── qbt-exporter     (ghcr.io/esanchezm/prometheus-qbittorrent-exporter:latest)
└── gluetun-exporter (ghcr.io/crstian19/gluetun-exporter:0.1.1)
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

## *arr Download Client Integration

qBittorrent and the *arr apps mount the **same NAS SMB share** at different container paths:

| App | SMB mount point | NAS torrents path |
|-----|-----------------|-------------------|
| qBittorrent | `/data` | `/data/torrents/` = NAS `/volume1/data/torrents/` |
| Radarr | `/data/media` | `/data/media/torrents/` = NAS `/volume1/data/torrents/` |
| Sonarr | `/data/media` | `/data/media/torrents/` = NAS `/volume1/data/torrents/` |

Both paths resolve to the **same physical directory** on the NAS. Use **Remote Path Mapping** in
Radarr/Sonarr to bridge the two container views.

### 1. Add qBittorrent as Download Client

In Radarr and Sonarr: `Settings → Download Clients → +`

- **Host**: `qbittorrent.qbittorrent.svc.cluster.local`
- **Port**: `8080`
- **Username / Password**: match the `qbittorrent-credentials` secret values
- **Category (Radarr)**: `movies` — saves to `/data/torrents/movies/`
- **Category (Sonarr)**: `tv` — saves to `/data/torrents/tv/`

### 2. Configure Remote Path Mapping

In Radarr: `Settings → Download Clients → Remote Path Mappings → +`

| Field | Value |
|-------|-------|
| Host | `qbittorrent.qbittorrent.svc.cluster.local` |
| Remote Path | `/data/torrents/` |
| Local Path | `/data/media/torrents/` |

Add the same mapping in Sonarr.

This maps qBittorrent's view (`/data/torrents/`) to Radarr/Sonarr's view (`/data/media/torrents/`),
both pointing to NAS `/volume1/data/torrents/`.

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
