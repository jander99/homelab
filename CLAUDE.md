# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Architecture

This is a homelab infrastructure repository managing both Docker services and a K3s Kubernetes cluster. The codebase is transitioning from Docker-based services to a GitOps-managed K3s cluster.

### Key Components

**Docker Services** (Legacy/Migration Reference):
- `/media/` - Media automation stack (Sonarr, Radarr, Prowlarr, NZBGet) with Prometheus exporters
- `/prometheus/` - Monitoring stack with Prometheus, Node Exporter, and SNMP exporter
- `/grafana/` - Grafana dashboard service with datasource configuration
- `/pihole/` - DNS ad-blocking service
- `/transmission/` - BitTorrent client
- `/portainer/` - Docker management interface
- `/watchtower/` - Automated container updates
- `/netgear-cm1000-exporter/` - Custom modem metrics exporter
- `/sense-exporter/` - Home energy monitoring exporter

**K3s Cluster** (Target Architecture):
- 3-node HA cluster (192.168.1.40-42) with embedded etcd
- Longhorn distributed storage with 3-way replication
- Flux CD v2 for GitOps automation
- CDK8s for TypeScript-based Kubernetes manifest generation
- Comprehensive monitoring with Prometheus + Grafana + Loki

### Network Architecture

**Docker Networks**:
- `homelab_physical_network` - macvlan driver for 192.168.1.0/24 subnet
- `homelab_bridge_network` - bridge network for internal container communication
- Services use both networks: physical IPs for external access, bridge IPs for internal communication

**K3s Networks**:
- Pod CIDR: 10.42.0.0/16
- Service CIDR: 10.43.0.0/16
- CNI: Flannel

## Common Development Tasks

### Docker Services Management

Each service follows the pattern:
```bash
# Service directories contain *-compose.yml files
cd <service-directory>
docker-compose -f <service>-compose.yml up -d
```

Environment variables required:
- `IP_ADDR` - Host IP address
- `HOSTNAME` - Host hostname
- Service-specific variables (API keys, credentials)

### Network Setup

Initialize Docker networks:
```bash
./scripts/network-setup.sh
```

This creates the macvlan network for physical IP assignment to containers.

### K3s Cluster Operations

**Bootstrap Process**:
```bash
# Full cluster bootstrap (from k3s/bootstrap/ansible/)
ansible-playbook -i inventory/hosts site.yml

# Individual components
ansible-playbook -i inventory/hosts playbooks/provision-nodes.yml
ansible-playbook -i inventory/hosts playbooks/bootstrap-k3s.yml
ansible-playbook -i inventory/hosts playbooks/bootstrap-flux.yml
```

**GitOps Workflow**:
1. Commit changes to Git repository
2. Flux CD automatically syncs changes (1m interval for GitRepository)
3. Kustomizations handle infrastructure (10m), platform, and applications

**CDK8s Development**:
```bash
cd applications/cdk8s/
# Generate manifests from TypeScript
cdk8s synth
# Commit generated manifests for Flux to deploy
git add manifests/ && git commit -m "Update manifests"
```

### Monitoring and Troubleshooting

**Flux Operations**:
```bash
# Check all Flux resources
flux get all -A

# Force reconciliation
flux reconcile source git flux-system
```

**Longhorn Storage**:
- Monitor volume health through Longhorn UI
- Failed replicas trigger automatic rebuilds
- Use CRDs for programmatic backup/restore operations

**Common Issues**:
- Volume degradation: Delete failed replicas to trigger rebuilds
- Node join failures: Check k3s service status and firewall rules
- Flux sync issues: Check GitRepository and Kustomization status

## Migration Strategy

The repository supports gradual migration from Docker to K3s:

1. **Assessment**: Document existing Docker service configurations
2. **Preparation**: Create K8s namespaces, PVCs, secrets, and networking
3. **Data Migration**: Use Jobs to copy data from Docker volumes to Longhorn PVCs
4. **Deployment**: Deploy K8s manifests with thorough testing
5. **Cutover**: Stop Docker services and update routing

## File Patterns

- `*-compose.yml` - Docker Compose service definitions
- `k3s/` - Kubernetes manifests and configuration
- `scripts/` - Infrastructure automation scripts
- `*/etc/` - Service-specific configuration files
- `prometheus/` - Monitoring configuration and alerting rules

## Security Considerations

- SOPS encryption with age keys for secrets management
- Network policies enforce default deny ingress
- RBAC limits developer access to read-only operations
- Let's Encrypt certificates via cert-manager for TLS
- Regular automated backups with Velero and Longhorn snapshots