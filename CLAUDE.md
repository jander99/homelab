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

**K3s Cluster** (Planned Target Architecture):
- 3-node HA cluster (192.168.1.40-42) with embedded etcd
- Flux CD v2 for GitOps automation rooted at `k3s/clusters/homelab/`
- Nx + CDK8s for TypeScript-based manifest authoring and render orchestration
- Manual platform and infrastructure manifests under `k3s/platform/` and `k3s/infrastructure/`
- Rendered workload manifests committed under `k3s/applications/`
- Monitoring remains centered on Prometheus + Grafana unless the repo later adopts additional tooling
- Storage decisions kept vendor-neutral until a real CSI choice is needed

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
# Phase 1 and Phase 2 are runnable today; Phase 3 still stops at the Flux stub.
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Individual components
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-flux.yml
```

**GitOps Workflow** _(target-state, once Nx workspace and cluster root exist)_:
1. Change manual cluster manifests or CDK8s source in Git
2. Run `nx run cdk8s:synth` to render workload YAML into `k3s/applications/`
3. Commit both source and rendered output
4. Flux CD syncs `k3s/clusters/homelab/`
5. Kustomizations reconcile platform, infrastructure, then applications

**CDK8s Development** _(target-state — `nx.json` and `applications/cdk8s/` do not exist yet)_:
```bash
# From the repo root
nx run cdk8s:synth
nx run cdk8s:validate

# Review rendered manifests before commit
git diff -- k3s/applications
```

Flux must never watch `applications/cdk8s/` directly; it should only reconcile the committed YAML under `k3s/clusters/homelab/`.
Until the Nx workspace and cluster root are created, skip the CDK8s commands above.

### Monitoring and Troubleshooting

**Flux Operations** _(target-state — Flux is not yet bootstrapped; `k3s/clusters/homelab/` does not exist)_:
```bash
# Check all Flux resources
flux get all -A

# Force reconciliation
flux reconcile source git flux-system
```

**Storage Guidance**:
- Keep shared manifests and constructs vendor-neutral
- Only set `storageClassName` when a workload actually needs it
- If a future CSI is adopted, isolate provider-specific config under `k3s/infrastructure/`

**Common Issues**:
- Rendered manifest drift _(future, once CDK8s workspace exists)_: Re-run `nx run cdk8s:synth` and review `git diff -- k3s/applications`
- Kustomize build failures _(future, once cluster root exists)_: Run `kustomize build k3s/clusters/homelab`
- Node join failures: Check k3s service status and firewall rules
- Flux sync issues _(future, once Flux is bootstrapped)_: Check GitRepository and Kustomization status

## Migration Strategy

The repository supports gradual migration from Docker to K3s:

1. **Assessment**: Document existing Docker service configurations
2. **Preparation**: Create K8s namespaces, PVCs, secrets, and networking
3. **Data Migration**: Use Jobs or one-off tooling to copy data from Docker volumes into the target PVCs or mounts required by the workload
4. **Deployment**: Deploy K8s manifests with thorough testing
5. **Cutover**: Stop Docker services and update routing

## File Patterns

- `*-compose.yml` - Docker Compose service definitions
- `k3s/` - Kubernetes manifests and configuration
- `scripts/` - Infrastructure automation scripts
- `*/etc/` - Service-specific configuration files
- `prometheus/` - Monitoring configuration and alerting rules

## Security Considerations

These are target-state controls for the planned GitOps cluster, not capabilities that already exist in the repo today:

- SOPS + age is the planned secrets model once Flux bootstrap is implemented
- Network policies should default to deny when cluster workloads start landing in K3s
- RBAC should be introduced with the platform layer rather than assumed to exist already
- cert-manager is the planned TLS automation layer when ingress moves to K3s
- Backups should be defined once the cluster storage and recovery approach are real, whether that ends up being Velero or something provider-specific