# MEDIA DIRECTORY

**Generated:** 2026-05-05

## OVERVIEW

Consolidated media automation stack: NZBGet (Usenet), Radarr (movies), Sonarr (TV), Prowlarr (indexers). All 4 services plus 3 exporters (Radarr, Sonarr, NZBGet) live in a single `media-compose.yml`. Prowlarr has no exporter. All containers use static bridge IPs.

## STRUCTURE

```
media/
└── media-compose.yml   # 4 services + 3 exporters (7 containers)
```

No `.env.example` — required env vars are documented by comments inside `media-compose.yml`.

## SERVICE TABLE

| Container | Image | Bridge IP | Port | Exporter IP | Exporter Port |
|-----------|-------|-----------|------|-------------|---------------|
| nzbget | linuxserver/nzbget | 172.20.0.15 | 6789 | 172.20.1.15 | 9452 |
| radarr | linuxserver/radarr | 172.20.0.16 | 7878 | 172.20.1.16 | 9708 |
| sonarr | linuxserver/sonarr | 172.20.0.17 | 8989 | 172.20.1.17 | 9709 |
| prowlarr | linuxserver/prowlarr | 172.20.0.18 | 9696 | — | — |

IP pattern: service at `172.20.0.1X`, exporter at `172.20.1.1X`.

## EXPORTER IMAGES

- **Radarr/Sonarr**: `ghcr.io/onedr0p/exportarr` — same image, different entrypoint command (`radarr` or `sonarr`)
- **NZBGet**: `frebib/nzbget-exporter` — connects to NZBGet via `NZBGET_HOST=http://172.20.0.15:6789`
- **Prowlarr**: no exporter exists; no stable metrics endpoint available

## REQUIRED ENV VARS (in sibling `.env` file)

| Variable | Used By |
|----------|---------|
| `NZBGET_USER` | nzbget healthcheck + nzbget-exporter |
| `NZBGET_PASS` | nzbget healthcheck + nzbget-exporter |
| `RADARR_API_KEY` | radarr healthcheck + exportarr |
| `SONARR_API_KEY` | sonarr healthcheck + exportarr |
| `PUID=1027`, `PGID=100`, `TZ=America/New_York` | all LinuxServer.io containers |

## DATA PATHS

| Service | Config | Data |
|---------|--------|------|
| nzbget | `/volume1/docker/config/nzbget` | `/volume1/data/usenet` → `/data/usenet` |
| radarr | `/volume1/docker/config/radarr` | `/volume1/data` → `/data` |
| sonarr | `/volume1/docker/config/sonarr` | `/volume1/data` → `/data` |
| prowlarr | `/volume1/docker/config/prowlarr` | `/volume1/data` → `/data` |

Radarr/Sonarr/Prowlarr share the `/volume1/data` bind mount so they can access the same media library.

## ANTI-PATTERNS

- **Prowlarr healthcheck is commented out** — its health endpoint was not stable; do not uncomment.
- **Do not add a Prowlarr exporter** — no stable metrics endpoint exists for Prowlarr.
- **Do not add media containers to the physical network** — bridge-only for all media services.
- **Do not change exporter IPs** without also updating `docker/prometheus/etc/prometheus.yml` scrape targets.

## NOTES

- Prowlarr acts as the indexer aggregator for Radarr and Sonarr; it does not have its own download client.
- All *arr services healthcheck via their own `/api/v3/system/status?apikey=` endpoint.
- NZBGet uses basic auth for the healthcheck; exportarr uses API key auth.
