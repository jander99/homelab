# PROJECT KNOWLEDGE BASE

**Generated:** 2026-05-02  
**Branch:** master  

## OVERVIEW
Homelab infrastructure managing 9 Docker services on a Synology NAS (macvlan networking), with a single-node K3s cluster bootstrap (Ansible) and documented plans to migrate to HA. Docker stack is operational; K3s server role is implemented; Flux CD and CDK8s remain future work.

## STRUCTURE
```
homelab/
├── media/              # Sonarr, Radarr, Prowlarr, NZBGet + exportarr exporters
├── prometheus/         # Prometheus + Node Exporter + alerting + SNMP config
├── grafana/            # Grafana with Prometheus datasource provisioning
├── pihole/             # Pi-hole + cloudflared (DoH) + exporter
├── transmission/       # Transmission-OpenVPN + exporter
├── portainer/          # Portainer Docker management UI
├── watchtower/         # Auto-update containers, daily 2am schedule
├── sense-exporter/     # Sense home energy monitor Prometheus exporter
├── netgear-cm1000-exporter/  # Netgear CM1000 cable modem exporter
├── k3s/                # Ansible K3s server bootstrap (single-node); Flux/HA planned
├── scripts/            # network-setup.sh: creates macvlan Docker network
├── CLAUDE.md           # AI agent instructions
└── README.md
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Add/modify a Docker service | `<service>/<service>-compose.yml` | Except: `sense-exporter/sense-exporter.yml` |
| Prometheus scrape targets | `prometheus/etc/prometheus.yml` | Static configs, bridge IPs |
| Alerting rules | `prometheus/etc/alerts.yml` | Currently only InstanceDown alert |
| SNMP exporter config | `prometheus/snmp_exporter/snmp.yml` | Auto-generated; job commented out in compose |
| Grafana datasource | `grafana/datasources/prometheus_ds.yml` | Points to `http://prometheus:9090` |
| Network initialization | `scripts/network-setup.sh` | Run before starting any services |
| K3s cluster bootstrap | `k3s/bootstrap/ansible/` | Single-node K3s server role implemented; Flux/HA planned |

## NETWORKING
Two external Docker networks (must exist before services start):

| Network | Driver | Subnet | Purpose |
|---------|--------|--------|---------|
| `homelab_physical_network` | macvlan | 192.168.1.0/24, gw .1, range /28 | Physical LAN IPs for services |
| `homelab_bridge_network` | bridge | 172.20.0.0/16 | Internal container-to-container |

- Services needing physical LAN presence (prometheus: 192.168.1.3, pihole: 192.168.1.2) join both networks.
- Exporters communicate to their parent service via static bridge IPs (e.g., radarr at 172.20.0.16, radarr-exporter at 172.20.1.16).
- **Create networks first**: `./scripts/network-setup.sh` (creates macvlan only; bridge created manually or via other compose).

## CONVENTIONS
- **Compose files**: Named `<service>-compose.yml`, NOT `docker-compose.yml`. Exception: `sense-exporter.yml`.
- **External networks**: All compose files reference networks as `external: name: homelab_bridge_network`.
- **LinuxServer.io containers**: Always `PUID=1027`, `PGID=100`, `TZ=America/New_York`.
- **Data paths**: All persistent data at `/volume1/data/<service>` and `/volume1/docker/config/<service>` (Synology NAS).
- **Exporter pattern**: Each stateful service (Sonarr, Radarr, NZBGet, etc.) has a paired exporter container in the same compose file.
- **Secrets**: Via `.env` file alongside compose file (gitignored by `**/*.env`). Variables like `${RADARR_API_KEY}`, `${NORDVPN_USER}`.

## ANTI-PATTERNS (THIS PROJECT)
- **Do not** use standard `docker-compose.yml` naming — breaks the `<service>-compose.yml` convention.
- **Do not** hardcode secrets in compose files — use `${VAR}` referencing `.env`.
- **Do not** use host networking or named volumes — bind mounts to `/volume1/` only.
- **Do not** assume K3s cluster exists on target hosts — Ansible provisions and installs K3s, but verify nodes are reachable first.
- **snmp.yml is auto-generated** — do not hand-edit it (`WARNING: This file was auto-generated`).
- **Typo in watchtower**: `WATHCTOWER_REVIVE_STOPPED` (misspelled) — do not "fix" it, it may break things.

## UNIQUE STYLES
- Watchtower Prometheus metrics require `Bearer` token auth at `/v1/metrics` (different from all other `/metrics` paths).
- Sense/CM1000 exporters use `/` as metrics path (not `/metrics`).
- Pi-hole DNS chain: Pi-hole → cloudflared (172.20.1.1:5053, DoH to 1.1.1.1).
- Node Exporter runs in privileged mode with proc/sys mounts; explicitly excludes Synology volume mount points.
- git-crypt is configured but encrypts only `*.gpg` files.

## COMMANDS
```bash
# Initialize networks (run once before first deploy)
./scripts/network-setup.sh

# Start a service
cd <service>/
docker-compose -f <service>-compose.yml up -d

# Example: start monitoring stack
cd prometheus/
docker-compose -f prometheus-compose.yml up -d
```

## NOTES
- **K3s bootstrap implemented**: `k3s/bootstrap/ansible/` has runnable `provision-nodes.yml` and `bootstrap-k3s.yml` (single-node K3s server role). `bootstrap-flux.yml` remains a stub. See `k3s/AGENTS.md` for current status.
- **Prowlarr healthcheck is commented out** — its health endpoint wasn't stable.
- **SNMP scrape is commented out** in `prometheus-compose.yml` — the config exists but the job is disabled.
- **Nginx proxy config** (`prometheus/syno-prom-proxy.conf`) is co-located with Prometheus, not in a separate nginx service.
- Required env vars per service documented in each `*-compose.yml` — no centralized `.env.example`.
