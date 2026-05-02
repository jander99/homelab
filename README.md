# Homelab Infrastructure

This repository manages Docker-based services on a Synology NAS and a single-node K3s cluster on a testbed machine. The infrastructure includes monitoring, media automation, networking services, and documented plans for migrating to a multi-node K3s cluster with GitOps.

## Architecture Overview

### Current Setup
- **Docker Services**: Legacy services running on Docker with macvlan networking
- **K3s Cluster**: Single-node testbed (192.168.1.128) with SQLite datastore; HA cluster planned — see `k3s/BOOTSTRAP.md` Part 2
- **Monitoring**: Comprehensive observability with Prometheus, Grafana, and custom exporters
- **Network**: 192.168.1.0/24 physical network with bridge networking for containers

### Repository Structure

```
homelab/
├── docker/                   # All Docker-based services
│   ├── media/                # Media automation stack (Sonarr, Radarr, etc.)
│   ├── prometheus/           # Monitoring and metrics collection
│   ├── grafana/              # Dashboards and visualization
│   ├── pihole/               # DNS ad-blocking
│   ├── transmission/         # BitTorrent client
│   ├── portainer/            # Docker management UI
│   ├── watchtower/           # Automated container updates
│   ├── sense-exporter/       # Energy monitoring metrics
│   ├── netgear-cm1000-exporter/  # Modem metrics
│   └── scripts/              # Docker network setup scripts
├── k3s/                      # Kubernetes cluster configuration and docs
└── README.md
```

## K3s Kubernetes Cluster

### Current State
- **Node**: Single testbed machine at 192.168.1.128
- **Datastore**: SQLite (default for single node)
- **GitOps**: Not yet implemented (Flux CD stub exists)
- **Storage**: Local-path provisioner only; future CSI choice is intentionally undecided
- **Networking**: Flannel VXLAN CNI
- **Ingress**: Traefik (default K3s ingress; Nginx planned)

### Planned (see `k3s/BOOTSTRAP.md` Part 2 and `k3s/k3s.md`)
- 3-node HA with embedded etcd
- Flux CD v2 GitOps rooted at `k3s/clusters/homelab/`
- Nx + CDK8s workflow that renders workload manifests into `k3s/applications/`
- Nginx Ingress + cert-manager

See `k3s/k3s.md` for the concrete repo blueprint and Flux reconciliation graph.

## Docker Services

### Infrastructure Services

#### Prometheus Stack
Comprehensive monitoring and alerting:
- **Prometheus**: Metrics collection and storage
- **Node Exporter**: System metrics from Synology NAS
- **Custom Exporters**: Service-specific metrics

#### Grafana
Visualization and dashboards with Prometheus datasource integration.

#### Pi-hole
Network-wide ad blocking DNS server running on physical network IP.

### Media Automation

Complete media management pipeline:
- **Sonarr**: TV series management and automation
- **Radarr**: Movie management and automation
- **Prowlarr**: Indexer management for *arr applications
- **NZBGet**: Usenet downloader
- **Transmission**: BitTorrent client

Each service includes dedicated Prometheus exporters for monitoring.

### Utility Services

- **Portainer**: Docker container management interface
- **Watchtower**: Automated container updates
- **Sense Exporter**: Home energy monitoring integration
- **Netgear CM1000 Exporter**: Cable modem metrics

## Network Configuration

### Docker Networks
Services use dual networking approach:
- **Physical Network**: `homelab_physical_network` (macvlan, 192.168.1.0/24)
- **Bridge Network**: `homelab_bridge_network` (internal container communication)

### Setup
Initialize Docker networks:
```bash
./docker/scripts/network-setup.sh
```

### Required Environment Variables
- `IP_ADDR`: Host IP address
- `HOSTNAME`: Host hostname
- Service-specific API keys and credentials

## Getting Started

### Docker Services
Each service directory contains a `*-compose.yml` file:
```bash
cd docker/<service-directory>
docker-compose -f <service>-compose.yml up -d
```

### K3s Cluster
Bootstrap the single-node cluster (run in order):
```bash
cd k3s/bootstrap/ansible/

# Step 1: OS hardening and K3s prerequisites (required first)
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml

# Step 2: Install K3s server
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml
```

## Migration to K3s

The repository documents a future migration from Docker to Kubernetes with:
- Single-node to HA cluster upgrade path (see `k3s/BOOTSTRAP.md` Part 2)
- Data migration tooling (planned)
- Service-by-service transition capability (planned)

See [`k3s/k3s.md`](k3s/k3s.md) for the full target architecture and [`k3s/BOOTSTRAP.md`](k3s/BOOTSTRAP.md) for current deployment status.


