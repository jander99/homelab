# Homelab Infrastructure

This repository manages both Docker-based services and a K3s Kubernetes cluster for my homelab environment. The infrastructure includes monitoring, media automation, networking services, and is transitioning to a GitOps-managed Kubernetes setup.

## Architecture Overview

### Current Setup
- **Docker Services**: Legacy services running on Docker with macvlan networking
- **K3s Cluster**: 3-node HA Kubernetes cluster with Longhorn storage and Flux CD GitOps
- **Monitoring**: Comprehensive observability with Prometheus, Grafana, and custom exporters
- **Network**: 192.168.1.0/24 physical network with bridge networking for containers

### Repository Structure

```
homelab/
├── docker-services/           # Docker Compose services
│   ├── media/                # Media automation stack (Sonarr, Radarr, etc.)
│   ├── prometheus/           # Monitoring and metrics collection
│   ├── grafana/              # Dashboards and visualization
│   ├── pihole/               # DNS ad-blocking
│   ├── transmission/         # BitTorrent client
│   ├── portainer/            # Docker management UI
│   ├── watchtower/           # Automated container updates
│   ├── sense-exporter/       # Energy monitoring metrics
│   └── netgear-cm1000-exporter/ # Modem metrics
├── k3s/                      # Kubernetes cluster configuration
├── scripts/                  # Infrastructure automation
└── k3s.md                   # Detailed K3s cluster documentation
```

## K3s Kubernetes Cluster

### Quick Overview
- **Nodes**: 3x Dell Optiplex (192.168.1.40-42)
- **Storage**: Longhorn distributed storage with 3-way replication
- **GitOps**: Flux CD v2 with CDK8s TypeScript manifests  
- **Monitoring**: Prometheus + Grafana + Loki stack
- **Networking**: Nginx Ingress with Let's Encrypt certificates

See [k3s.md](k3s.md) for comprehensive documentation on cluster architecture, deployment, and operations.

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
./scripts/network-setup.sh
```

### Required Environment Variables
- `IP_ADDR`: Host IP address
- `HOSTNAME`: Host hostname  
- Service-specific API keys and credentials

## Getting Started

### Docker Services
Each service directory contains a `*-compose.yml` file:
```bash
cd <service-directory>
docker-compose -f <service>-compose.yml up -d
```

### K3s Cluster
Bootstrap the entire cluster:
```bash
cd k3s/bootstrap/ansible/
ansible-playbook -i inventory/hosts site.yml
```

## Migration to K3s

The repository supports gradual migration from Docker to Kubernetes with:
- Data migration tooling
- Service-by-service transition capability
- Rollback procedures
- Comprehensive testing workflows

See [k3s.md](k3s.md) for detailed migration procedures and GitOps workflows.  


