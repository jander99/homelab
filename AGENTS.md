# PROJECT KNOWLEDGE BASE

**Generated:** 2026-05-06  
**Branch:** master  

## OVERVIEW
Homelab infrastructure managing 9 Docker services on a Synology NAS (macvlan networking), with a single-node K3s cluster (Ansible-bootstrapped) and Flux CD v2 GitOps with infrastructure deployed (cert-manager, metallb, headlamp, kube-prometheus-stack). Docker stack is operational; K3s cluster running on testbed node (192.168.1.128) with Flux managing controllers, a full monitoring stack (Prometheus + Grafana + Alertmanager), and applications (headlamp, pihole). CDK8s/Nx workspace initialized but contains only a stub chart.

## STRUCTURE
```
homelab/
├── docker/             # All Docker-based services — see docker/AGENTS.md
│   ├── media/          # Sonarr, Radarr, Prowlarr, NZBGet + exporters — see media/AGENTS.md
│   ├── prometheus/     # Prometheus + Node Exporter + alerting — see prometheus/AGENTS.md
│   ├── grafana/        # Grafana with Prometheus datasource provisioning
│   ├── pihole/         # Pi-hole + cloudflared (DoH) + exporter
│   ├── transmission/   # Transmission-OpenVPN + exporter
│   ├── portainer/      # Portainer Docker management UI
│   ├── watchtower/     # Auto-update containers, daily 2am schedule
│   ├── sense-exporter/ # Sense home energy monitor Prometheus exporter
│   ├── netgear-cm1000-exporter/  # Netgear CM1000 cable modem exporter
│   └── scripts/        # network-setup.sh: creates macvlan Docker network
├── k3s/                # K3s bootstrap (Ansible) + Flux GitOps with deployed infrastructure
├── applications/
│   └── cdk8s/          # CDK8s TypeScript stub (HelloChart only) — see cdk8s/AGENTS.md
├── .sops.yaml          # SOPS age encryption rules for K3s secrets
└── README.md
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Add/modify a Docker service | `docker/<service>/<service>-compose.yml` | Except: `docker/sense-exporter/sense-exporter.yml`; see `docker/AGENTS.md` for full service table |
| Prometheus scrape targets | `docker/prometheus/etc/prometheus.yml` | Static configs, bridge IPs |
| Alerting rules | `docker/prometheus/etc/alerts.yml` | Currently only InstanceDown alert |
| SNMP exporter config | `docker/prometheus/snmp_exporter/snmp.yml` | Auto-generated; job commented out in compose |
| Grafana datasource | `docker/grafana/datasources/prometheus_ds.yml` | Points to `http://prometheus:9090` |
| Network initialization | `docker/scripts/network-setup.sh` | Run before starting any services |
| K3s cluster bootstrap | `k3s/bootstrap/ansible/` | Single-node K3s server role implemented; provision-nodes + bootstrap-k3s runnable |
| Flux Kustomizations | `k3s/clusters/homelab/` | Reconciliation graph: platform → infra-controllers → infra-configs → apps |
| Flux system manifests | `k3s/clusters/homelab/flux-system/` | Flux v2.3.0; GitRepository watches `master` branch |
| SOPS/age config | `.sops.yaml` | age key encryption; see k3s/AGENTS.md for key fingerprint |
| Headlamp app | `k3s/applications/headlamp/` | headlamp.homelab.properties; TLS via letsencrypt-prod |
| Pihole app | `k3s/applications/pihole/` | pihole.homelab.properties; DNS + PodMonitor enabled |
| Monitoring stack (K3s) | `k3s/infrastructure/configs/monitoring/` | kube-prometheus-stack HelmRelease; grafana/prometheus/alertmanager.homelab.properties |
| Grafana (K3s) | https://grafana.homelab.properties | Credentials in BitWarden; SOPS secret at `grafana-secret.sops.yaml` |
| K3s infrastructure controllers | `k3s/infrastructure/controllers/` | cert-manager + metallb HelmReleases; see `k3s/infrastructure/AGENTS.md` |
| K3s infrastructure controllers | `k3s/infrastructure/controllers/` | cert-manager + metallb HelmReleases; see `k3s/infrastructure/AGENTS.md` |

## NETWORKING
Two external Docker networks (must exist before services start):

| Network | Driver | Subnet | Purpose |
|---------|--------|--------|---------|
| `homelab_physical_network` | macvlan | 192.168.1.0/24, gw .1, range /28 | Physical LAN IPs for services |
| `homelab_bridge_network` | bridge | 172.20.0.0/16 | Internal container-to-container |

- Services needing physical LAN presence (prometheus: 192.168.1.3, pihole: 192.168.1.2) join both networks.
- Exporters communicate to their parent service via static bridge IPs (e.g., radarr at 172.20.0.16, radarr-exporter at 172.20.1.16).
- **Create networks first**: `./docker/scripts/network-setup.sh` (creates macvlan only; bridge created manually or via other compose).

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
- git-crypt is configured but encrypts only `*.gpg` files. K3s secrets use SOPS+age (`.sops.yaml`).

## COMMANDS
```bash
# Initialize networks (run once before first deploy)
./docker/scripts/network-setup.sh

# Start a service
cd docker/<service>/
docker-compose -f <service>-compose.yml up -d

# Example: start monitoring stack
cd docker/prometheus/
docker-compose -f prometheus-compose.yml up -d
```

## NOTES
- **K3s + Flux**: `bootstrap-k3s.yml` installs single-node K3s on testbed (192.168.1.128); `bootstrap-flux.yml` bootstraps Flux against `k3s/clusters/homelab/` with cert-manager, metallb (infra controllers), kube-prometheus-stack (infra configs), pihole, and headlamp (applications) deployed. See `k3s/AGENTS.md` and `k3s/infrastructure/AGENTS.md`.
- **Prowlarr healthcheck is commented out** — its health endpoint wasn't stable.
- **SNMP scrape is commented out** in `prometheus-compose.yml` — the config exists but the job is disabled.
- **Nginx proxy config** (`docker/prometheus/syno-prom-proxy.conf`) is co-located with Prometheus, not in a separate nginx service.
- Required env vars per service documented in each `*-compose.yml` — no centralized `.env.example`.
- **CDK8s/Nx**: Workspace initialized (Yarn 4.14.1, nx.json); `applications/cdk8s/src/main.ts` is a HelloChart stub only. Synth target configured. No real workloads; dist/ → k3s/applications/ promotion not yet designed. See `applications/cdk8s/AGENTS.md`.
