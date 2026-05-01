# PROMETHEUS DIRECTORY

## OVERVIEW
Prometheus monitoring stack: metrics collection, alerting, SNMP config, and Nginx proxy configuration for the homelab.

## STRUCTURE
```
prometheus/
├── prometheus-compose.yml   # Prometheus + Node Exporter services
├── etc/
│   ├── prometheus.yml       # Scrape configs (10 jobs)
│   └── alerts.yml           # Alerting rules (currently: InstanceDown only)
├── snmp_exporter/
│   └── snmp.yml             # Auto-generated SNMP config for Synology
└── syno-prom-proxy.conf     # Nginx reverse proxy config (not a separate service)
```

## WHERE TO LOOK
| Task | File | Notes |
|------|------|-------|
| Add a scrape target | `etc/prometheus.yml` | Use bridge IP or container name |
| Add/modify alerts | `etc/alerts.yml` | Single group `DemoAlerts` today |
| SNMP config | `snmp_exporter/snmp.yml` | **Do not hand-edit** — auto-generated |
| Prometheus/Node Exporter config | `prometheus-compose.yml` | |

## SCRAPE ENDPOINTS (non-obvious paths)
| Job | Target | Path | Auth |
|-----|--------|------|------|
| watchtower | `watchtower:8080` | `/v1/metrics` | Bearer token |
| sense | `sense-exporter:9993` | `/` | none |
| cm1000 | `cm1000-exporter:9527` | `/` | none |
| all others | `<container>:<port>` | `/metrics` | none |

## NETWORKING
- Prometheus joins **both** networks: physical (192.168.1.3) + bridge (172.20.1.3).
- Node Exporter container name `syno_node_exporter` (underscore, not hyphen) — matches scrape target name in `prometheus.yml`.
- All exporter targets use bridge IPs or container names — never host IPs.

## ANTI-PATTERNS
- **Do not hand-edit `snmp.yml`** — auto-generated; file header says so.
- **SNMP scrape job is commented out** in `prometheus-compose.yml` — do not uncomment without verifying SNMP exporter service is running.
- **Do not add the physical-network IP** as a Prometheus scrape target — use bridge network names/IPs.

## NOTES
- Only one alert rule exists (`InstanceDown` on `job="services"` for 5m). Alerting is minimal.
- `syno-prom-proxy.conf` is an Nginx config co-located here for convenience — no Nginx container is defined in this directory.
- Grafana connects to Prometheus via `http://prometheus:9090` (bridge network container name).
