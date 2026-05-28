# Homelab Media Stack Integration Guide

This guide details the configuration required to link Prowlarr, Sonarr, Radarr, and download clients within the Docker and K3s environment. It focuses on the bridge network connectivity and path consistency necessary for hardlinks to function.

## 1. Architecture Overview

The following diagram illustrates the flow of metadata and media files through the stack. Indexers are centralized in Prowlarr, synced to the \*arr apps, which then send tasks to download clients. Files are moved via atomic moves or hardlinks on the shared NAS volume.

```text
                          [ Indexers ]
                               |
                               v
                        [ Prowlarr ]
                        172.20.0.18
                               |
              +----------------+----------------+
              |                                 |
    (Sync Indexers)                    (Sync Indexers)
              |                                 |
              v                                 v
         [ Sonarr ]                       [ Radarr ]
         172.20.0.17                      172.20.0.16
              |                                 |
              +----------------+----------------+
                               |
              +----------------+----------------+
              |                                 |
     (Send Downloads)                 (Send Downloads)
              |                                 |
              v                                 v
       [ qBittorrent ]                   [ NZBGet ]
         K3s Node                       172.20.0.15
              |                                 |
       /data/torrents               /data/usenet
              |                                 |
              +----------------+----------------+
                               |
                      (Import / Hardlink)
                               |
                               v
                       /volume1/data/media
                        (TV and Movies)
```

## 2. Prowlarr → Sonarr and Radarr (Indexer Sync)

Prowlarr acts as the single source of truth for indexers. Instead of adding indexers to Sonarr and Radarr individually, add them to Prowlarr and sync.

### Configuration in Prowlarr UI

Navigate to **Settings > Apps** and click the plus icon to add each application.

**Prowlarr Server:** `http://172.20.0.18:9696`

**Sonarr Instance:**

| Field          | Value                                      |
| -------------- | ------------------------------------------ |
| Sonarr Server  | `http://172.20.0.17:8989`                  |
| API Key        | Retrieve from Sonarr: Settings > General   |
| Sync Level     | Full Sync                                  |
| Sync Categories | 5000, 5030, 5040 (TV)                     |

**Radarr Instance:**

| Field          | Value                                      |
| -------------- | ------------------------------------------ |
| Radarr Server  | `http://172.20.0.16:7878`                  |
| API Key        | Retrieve from Radarr: Settings > General   |
| Sync Level     | Full Sync                                  |
| Sync Categories | 2000, 2010, 2040, 2045 (Movies)           |

### Sync Levels

- **Full Sync** — Prowlarr manages the entire indexer config in the target app. Recommended.
- **Add and Remove Only** — Prowlarr only adds/removes indexers; does not update settings in the target app.

> Always click **Test** after entering the API key. A green checkmark confirms containers can communicate over `homelab_bridge_network`.

## 3. Sonarr and Radarr → NZBGet (Usenet)

NZBGet runs in the same Docker bridge network. Use the static bridge IP.

### Configuration in Sonarr/Radarr UI

Navigate to **Settings > Download Clients** and add **NZBGet**.

| Field    | Sonarr Value      | Radarr Value      |
| -------- | ----------------- | ----------------- |
| Host     | `172.20.0.15`     | `172.20.0.15`     |
| Port     | `6789`            | `6789`            |
| Username | your NZBGet username  | your NZBGet username  |
| Password | your NZBGet password  | your NZBGet password  |
| Category | `tv`              | `movies`          |

> `NZBGET_USER` and `NZBGET_PASS` must match the **Control** credentials in NZBGet Security settings.

### Required NZBGet UI Settings

These cannot be set via Docker Compose and must be configured manually in the NZBGet UI.

**Settings > PATHS:**

```
MainDir:  /data/usenet
DestDir:  ${MainDir}/complete
InterDir: ${MainDir}/incomplete
```

**Settings > CATEGORIES:**

| Category | DestDir                        |
| -------- | ------------------------------ |
| `tv`     | `${MainDir}/complete/tv`       |
| `movies` | `${MainDir}/complete/movies`   |

**Settings > INCOMING NZBS:**

- **AppendCategoryDir:** `Yes`

### NAS Directory Prep

NZBGet will not reliably create nested directories. Ensure these exist on the NAS before first use:

```bash
mkdir -p /volume1/data/usenet/complete/tv
mkdir -p /volume1/data/usenet/complete/movies
mkdir -p /volume1/data/usenet/incomplete
```

## 4. Sonarr and Radarr → SABnzbd (K3s Usenet)

SABnzbd runs in the K3s cluster in the `sabnzbd` namespace. Sonarr and Radarr run in the `media` namespace, so use the Kubernetes service DNS name from the \*arr download client settings.

### Configuration in Sonarr/Radarr UI

Navigate to **Settings > Download Clients** and add **SABnzbd**.

| Field    | Sonarr Value                         | Radarr Value                         |
| -------- | ------------------------------------ | ------------------------------------ |
| Host     | `sabnzbd.sabnzbd.svc.cluster.local`  | `sabnzbd.sabnzbd.svc.cluster.local`  |
| Port     | `8080`                               | `8080`                               |
| API Key  | value from the SABnzbd UI/API secret | value from the SABnzbd UI/API secret |
| Category | `tv`                                 | `movies`                             |

### Required SABnzbd UI Settings

SABnzbd has a node-local `/downloads` PVC and a shared NAS `/data` SMB mount. Completed downloads must land on the shared NAS path so Sonarr and Radarr can import them from their own pods.

**Settings > Folders:**

```text
Temporary Download Folder: /downloads/incomplete
Completed Download Folder: /data/usenet/completed
```

**Settings > Categories:**

| Category | Folder                      |
| -------- | --------------------------- |
| `tv`     | `/data/usenet/completed/tv` |
| `movies` | `/data/usenet/completed/movies` |

The `/downloads` path is only for temporary/incomplete data. If SABnzbd reports completed files under `/downloads`, Sonarr and Radarr cannot access those files because `/downloads` is local to the SABnzbd pod.

### Path Mapping

The K3s manifests mount the shared NAS root at `/data` in SABnzbd, Sonarr, and Radarr. With completed folders under `/data/usenet/completed`, no Remote Path Mapping is required for SABnzbd. If the SABnzbd UI reports a different remote path, fix the SABnzbd folder/category settings rather than mapping a node-local `/downloads` path.

### NAS Directory Prep

Ensure these directories exist on the NAS before first use:

```bash
mkdir -p /volume1/data/usenet/completed/tv
mkdir -p /volume1/data/usenet/completed/movies
mkdir -p /volume1/data/usenet/incomplete
```

## 5. Sonarr and Radarr → qBittorrent (Torrents)

qBittorrent runs in the K3s cluster and is exposed via Ingress at `qbittorrent.homelab.properties`. Docker containers reach it over the LAN through the MetalLB-assigned Traefik IP.

### Configuration in Sonarr/Radarr UI

Navigate to **Settings > Download Clients** and add **qBittorrent**.

| Field    | Sonarr Value              | Radarr Value              |
| -------- | ------------------------- | ------------------------- |
| Host     | `qbittorrent.homelab.properties` | `qbittorrent.homelab.properties` |
| Port     | `443`                            | `443`                            |
| SSL      | Yes                              | Yes                              |
| Category | `tv`                      | `movies`                  |

### qBittorrent Category Paths (set in qBittorrent UI)

| Category | Save Path            |
| -------- | -------------------- |
| `tv`     | `/data/torrents/tv`  |
| `movies` | `/data/torrents/movies` |

### Seeding and Cleanup

- **Remove Completed:** Off (allow seeding to continue)
- **Remove Failed:** On
- Configure a minimum seeding ratio (e.g., 1.0) in qBittorrent; Sonarr/Radarr can stop the torrent once reached.

### Remote Path Mappings

If qBittorrent reports download paths that differ from what Sonarr/Radarr expect (e.g., `/downloads/tv/` vs `/data/torrents/tv/`), add a **Remote Path Mapping** in **Settings > Download Clients**:

| Field       | Value                     |
| ----------- | ------------------------- |
| Host        | `qbittorrent.homelab.properties` |
| Remote Path | `/downloads/`             |
| Local Path  | `/data/torrents/`         |

> For hardlinks to work, qBittorrent and the \*arr apps must resolve identical file paths. Confirm the K3s node mounts `/volume1/data` at `/data`.

## 6. Recyclarr

Recyclarr automates synchronization of quality profiles and custom formats from the TRaSH Guides. It runs as a K3s CronJob at 2:30am America/New_York using the config in `k3s/applications/recyclarr/configmap.yaml`.

### Recommended `recyclarr.yml`

```yaml
sonarr:
  tv:
    base_url: !env_var SONARR_BASE_URL
    api_key: !env_var SONARR_API_KEY
    delete_old_custom_formats: true
    replace_existing_custom_formats: true
    quality_definition:
      type: series
    quality_profiles:
      - trash_id: 72dae194fc92bf828f32cde7744e51a1
        reset_unmatched_scores:
          enabled: true
        upgrade_until_score: 10000
    include:
      - template: sonarr-quality-definition-series
      - template: sonarr-v4-quality-profile-web-1080p
      - template: sonarr-v4-custom-formats-web-1080p

radarr:
  movies:
    base_url: !env_var RADARR_BASE_URL
    api_key: !env_var RADARR_API_KEY
    delete_old_custom_formats: true
    replace_existing_custom_formats: true
    quality_definition:
      type: movie
    quality_profiles:
      - trash_id: d1d67249d3890e49bc12e275d989a7e9
        reset_unmatched_scores:
          enabled: true
        upgrade_until_score: 10000
    include:
      - template: radarr-quality-definition-movie
      - template: radarr-quality-profile-hd-bluray-web
      - template: radarr-custom-formats-hd-bluray-web
```

### Key Notes

- `delete_old_custom_formats: true` — removes stale TRaSH formats automatically; already set in the ConfigMap.
- `replace_existing_custom_formats: true` — updates scoring when guides change; already set in the ConfigMap.
- Secrets (`SONARR_API_KEY`, `RADARR_API_KEY`, etc.) are injected via the SOPS-encrypted secret in the same namespace.

### Manual Trigger

```bash
kubectl create job --from=cronjob/recyclarr recyclarr-manual -n <namespace>
```

## 7. Assessment

### What is Correct

| Item | Notes |
| ---- | ----- |
| Shared volume root | `/volume1/data` mounted as `/data` in all K3s media containers (sonarr, radarr, sabnzbd, qbittorrent); library is at `/data/media/tv` and `/data/media/movies` via this mount |
| Security | SOPS for K3s secrets; `.env` files for Docker prevents secrets in git |
| Static bridge IPs | Deterministic addressing; no DNS resolution dependency |
| Monitoring | Exportarr sidecar containers for Sonarr (9709) and Radarr (9708); NZBGet exporter (9452) |

### What Needs to Change

| Item | Action |
| ---- | ------ |
| NZBGet categories | Configure `tv` and `movies` categories manually in NZBGet UI for the Docker stack (see Section 3) |
| SABnzbd categories | Configure `tv` and `movies` categories manually in SABnzbd UI for the K3s stack (see Section 4) |
| Sonarr root folder | Set to `/data/media/tv` in Sonarr UI (Settings > Media Management > Root Folders) |
| Radarr root folder | Set to `/data/media/movies` in Radarr UI (Settings > Media Management > Root Folders) |
| NAS directories | Create `/volume1/data/usenet/complete/{tv,movies}` for Docker NZBGet and `/volume1/data/usenet/completed/{tv,movies}` for K3s SABnzbd before first use |
| Recyclarr ConfigMap | Flags `delete_old_custom_formats` and `replace_existing_custom_formats` are already `true` — no change needed |
| Prometheus config | Remove the stale `transmission-exporter` job from `docker/prometheus/etc/prometheus.yml` |

### What is Missing

| Item | Notes |
| ---- | ----- |
| FlareSolverr | Many indexers require Cloudflare bypass; add a FlareSolverr container (suggest `172.20.0.19`) to `media-compose.yml` and configure in Prowlarr |
| Prowlarr exporter | Prowlarr has no Prometheus exporter; indexer success rates and response times are unmonitored |
| Remote Path Mappings | May be required if a download client and \*arr apps resolve different paths for the same files; SABnzbd should instead complete to the shared `/data/usenet/completed` NAS path |
