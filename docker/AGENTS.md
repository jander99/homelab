# DOCKER DIRECTORY

**Generated:** 2026-05-05

## OVERVIEW

All Docker-based homelab services running on a Synology NAS with macvlan + bridge dual networking. 9 service groups; most stateful services have a paired Prometheus exporter. Physical LAN IPs are assigned to services that need to be addressable on the LAN (Prometheus, Pi-hole). All others use bridge-only networking.

## STRUCTURE

```
docker/
├── media/                          # media-compose.yml — 4 services + 3 exporters
├── prometheus/                     # prometheus-compose.yml + etc/ + snmp_exporter/ — see prometheus/AGENTS.md
├── grafana/                        # grafana-compose.yml
├── pihole/                         # pihole-compose.yml — Pi-hole + cloudflared + exporter
├── transmission/                   # transmission-compose.yml — OpenVPN + exporter
├── portainer/                      # portainer-compose.yml
├── watchtower/                     # watchtower-compose.yml
├── sense-exporter/                 # sense-exporter.yml  ← EXCEPTION: not *-compose.yml
├── netgear-cm1000-exporter/        # cm1000-compose.yml
└── scripts/                        # network-setup.sh + README.md
```

## SERVICE INVENTORY

| Service | Compose File | Physical IP | Bridge IP | Port | Exporter Bridge IP | Exporter Port |
|---------|-------------|-------------|-----------|------|--------------------|---------------|
| prometheus | prometheus-compose.yml | 192.168.1.3 | 172.20.1.3 | 9090 | — | — |
| syno_node_exporter | prometheus-compose.yml | — | bridge_mode | 9100 | — | — |
| pihole | pihole-compose.yml | 192.168.1.2 | 172.20.1.2 | DNS/80 | bridge_mode | 33302 |
| cloudflared | pihole-compose.yml | — | 172.20.1.1 | 5053,33301 | — | — |
| grafana | grafana-compose.yml | — | bridge_mode | 3000 | — | — |
| nzbget | media-compose.yml | — | 172.20.0.15 | 6789 | 172.20.1.15 | 9452 |
| radarr | media-compose.yml | — | 172.20.0.16 | 7878 | 172.20.1.16 | 9708 |
| sonarr | media-compose.yml | — | 172.20.0.17 | 8989 | 172.20.1.17 | 9709 |
| prowlarr | media-compose.yml | — | 172.20.0.18 | 9696 | — | — |
| transmission | transmission-compose.yml | — | bridge_mode | 9091 | bridge_mode | 19091 |
| portainer | portainer-compose.yml | — | bridge_mode | 8000,9000 | — | — |
| watchtower | watchtower-compose.yml | — | bridge_mode | 8080 | — | — |
| sense-exporter | sense-exporter.yml | — | bridge_mode | 9993 | — | — |
| cm1000-exporter | cm1000-compose.yml | — | bridge_mode | 9527 | — | — |

## NETWORK MEMBERSHIP

Services on **both** networks (macvlan + bridge):
- `prometheus`: 192.168.1.3 (physical) + 172.20.1.3 (bridge)
- `pihole`: 192.168.1.2 (physical) + 172.20.1.2 (bridge)
- `cloudflared`: bridge static IP 172.20.1.1 only

All other services: bridge network only (`network_mode: homelab_bridge_network` or static bridge IP).

Media stack IP pattern: service at 172.20.0.1X, exporter at 172.20.1.1X.

## NON-OBVIOUS QUIRKS

| Service | Quirk |
|---------|-------|
| watchtower | Metrics at `/v1/metrics`, requires `Authorization: Bearer <token>` — different from all others |
| sense-exporter | Metrics path is `/` not `/metrics` |
| cm1000-exporter | Metrics path is `/` not `/metrics`; polls modem at 192.168.100.1 |
| prowlarr | Healthcheck disabled (commented out) — endpoint was unstable |
| transmission | `cap_add: NET_ADMIN` + NordVPN; uses `links:` to reference openvpn container; LOCAL_NETWORK=192.168.1.0/24 |
| portainer | Mounts `/var/run/docker.sock` — requires Docker socket access |
| pihole | DNS chain: Pi-hole → cloudflared (172.20.1.1#5053 DoH to 1.1.1.1); DNS2=no |
| node exporter | privileged:true; mounts proc/sys; explicitly excludes Synology /volumeX mountpoints |

## CONVENTIONS

- **Compose naming**: `<service>-compose.yml`. Exceptions: `sense-exporter.yml` (no `*-compose.yml` alias exists — use as-is).
- **LinuxServer.io containers**: `PUID=1027`, `PGID=100`, `TZ=America/New_York` always.
- **Data paths**: `/volume1/data/<service>` and `/volume1/docker/config/<service>` on Synology.
- **Secrets**: `${VAR}` in compose referencing a sibling `.env` file (gitignored via `**/*.env`).
- **External networks**: always `external: name: homelab_bridge_network`.

## ANTI-PATTERNS

- **Do not** rename `sense-exporter.yml` to follow the convention without updating any tooling that references it.
- **Do not** use `docker-compose.yml` naming — breaks the project convention.
- **Do not** hardcode secrets in compose files — use `${VAR}` referencing `.env`.
- **Do not** use host networking or named volumes — bind mounts to `/volume1/` only.
- **WATHCTOWER_REVIVE_STOPPED** is intentionally misspelled in watchtower-compose.yml — do not fix it.

## COMMANDS

```bash
# Initialize networks once before first deploy
./docker/scripts/network-setup.sh

# Start any service
cd docker/<service>/
docker-compose -f <service>-compose.yml up -d

# Exception — sense exporter
cd docker/sense-exporter/
docker-compose -f sense-exporter.yml up -d
```
