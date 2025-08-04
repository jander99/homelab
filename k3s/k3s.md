# Homelab K3s GitOps Cluster

3-node k3s cluster on Dell Optiplex micros with Longhorn distributed storage.

## Hardware & Infrastructure
- **Nodes**: 3x Dell Optiplex (i5-8500T/8600T, 32GB RAM, SATA+NVMe storage)
- **IPs**: 192.168.1.40-42 (expandable to .43-.60)
- **Storage**: Longhorn on NVMe drives, 3-way replication, ~1.5TB usable
- **Resources**: ~84GB RAM, 12-15 cores available for workloads
- **Network**: Flannel CNI, 10.42.0.0/16 pod CIDR, 10.43.0.0/16 service CIDR

## Architecture & Stack
- **OS**: Ubuntu LTS, k3s (embedded etcd HA)
- **GitOps**: Flux CD v2, CDK8s (TypeScript), Ansible automation
- **Monitoring**: Prometheus + Grafana + Loki
- **Networking**: Nginx Ingress, cert-manager + Let's Encrypt

## Repository Structure
```
homelab/
├── k3s/
│   ├── bootstrap/ansible/     # Node provisioning & k3s install
│   ├── infrastructure/        # Longhorn, ingress, monitoring
│   ├── platform/             # Flux system & namespaces
│   ├── applications/         # CDK8s outputs & manifests
│   └── environments/         # dev/staging/prod overrides
├── docker/                   # Existing Docker services (migration reference)
└── scripts/                  # Network setup & utilities
```

## GitOps Workflow
**Bootstrap**: Ansible → k3s → Flux CD → Git-managed everything
**Deploy**: CDK8s TypeScript → manifests → Git commit → Flux sync
**Migrate**: Gradual Docker-to-k8s migration with rollback capability

## Quick Start
```bash
# Bootstrap cluster: ansible-playbook -i inventory/hosts site.yml
# Deploy changes: commit to Git, Flux auto-syncs
```

## Ansible Configuration

### Structure & Key Components
```
bootstrap/ansible/
├── inventory/hosts.yml       # Node definitions (IPs, roles, storage)
├── playbooks/
│   ├── provision-nodes.yml   # OS setup & prerequisites  
│   ├── bootstrap-k3s.yml     # K3s installation
│   ├── bootstrap-flux.yml    # Flux CD installation
│   └── site.yml             # Full cluster bootstrap
├── roles/                   # common, k3s-server, storage-prep
└── ansible.cfg
```

### Inventory Overview
- 3 nodes (192.168.1.40-42) as k3s servers with embedded etcd
- Each node uses `/dev/nvme0n1` for Longhorn storage
- Configures kernel modules (br_netfilter, overlay, iscsi_tcp)
- Sets required sysctl parameters for k8s networking

## Flux CD Setup

### Structure & Components
```
k3s/
├── clusters/homelab/           # Flux controllers & cluster entrypoint
├── infrastructure/             # Core services (cert-manager, nginx, longhorn)
├── platform/                  # Namespaces & RBAC
└── applications/               # App manifests with dev/prod overlays
```

### Configuration
- GitRepository watches `master` branch with 1m interval
- Kustomizations sync infrastructure (10m), platform, and applications
- SOPS encryption for secrets with age keys

## Longhorn Configuration
- **Default**: 3 replicas, /var/lib/longhorn path, S3 backups
- **Storage Classes**: longhorn (default, 3-replica) + longhorn-single-replica  
- **Nodes**: NVMe disks with 20Gi reserved space

## CDK8s Configuration

### TypeScript-based Kubernetes Manifests
```
applications/cdk8s/
├── src/
│   ├── main.ts                  # App entry point
│   ├── constructs/              # base-app.ts, stateful-app.ts, media-stack.ts
│   └── charts/                  # prometheus.ts, grafana.ts, arr-stack.ts
└── manifests/                   # Generated YAML output
```

### BaseApp Construct Features
- Generates Deployment, Service, and Ingress resources
- Configurable replicas, environment variables, and domains
- Auto-configured TLS with Let's Encrypt and cert-manager
- Build workflow: `cdk8s synth` → commit manifests → Flux sync

## Ingress & Certificate Management

### Nginx Ingress
- **Deployment**: DaemonSet with hostNetwork for direct node access
- **Configuration**: Forward headers enabled, Prometheus metrics
- **Resources**: 100m CPU request, 512Mi memory limit

### Cert-Manager
- **Issuers**: Let's Encrypt production & staging ClusterIssuers
- **Solver**: HTTP01 challenge via nginx ingress
- **Wildcard**: Optional wildcard certificate for `*.homelab.local`

## Security Configuration

### RBAC & Network Policies
- **Developer Role**: Read-only access to pods, services, deployments
- **Network Policies**: Default deny ingress, allow only ingress controller traffic
- **Secrets**: SOPS with age encryption for Git-stored secrets

### SOPS Encryption
```bash
# Encrypt: sops -e -i cluster-secrets.yaml
# Edit: sops cluster-secrets.yaml
```

## Backup & Disaster Recovery

### Velero Setup
- **Storage**: MinIO S3-compatible backend
- **Schedule**: Daily backups at 2 AM, 30-day retention
- **Scope**: All namespaces except kube-system/longhorn-system
- **Plugins**: AWS & CSI volume snapshot support

### Etcd Backups
- Automated snapshots on all control plane nodes
- 7-day retention policy
- Manual recovery: stop k3s → restore snapshot → rejoin cluster

### Longhorn Recovery
- Auto-healing replicas with health monitoring
- Snapshot-based point-in-time recovery
- S3 backups for disaster scenarios

## Service Migration Guide

### Migration Process
1. **Assessment**: Document Docker configs, volume requirements, dependencies
2. **Preparation**: Create k8s namespaces, configure PVCs, secrets, networking
3. **Data Migration**: Use Jobs to copy data from Docker volumes to Longhorn PVCs
4. **Deployment**: Deploy k8s manifests, test functionality, validate rollback
5. **Cutover**: Stop Docker service, final sync, update routing

### Migration Pattern
- Create PVC with Longhorn storage class
- Use migration Job to copy data from NFS/local mounts to PVC
- Deploy StatefulSet/Deployment with proper volume mounts
- Test thoroughly before final cutover

## Monitoring & Observability

### Prometheus Stack
- **Prometheus**: 30-day retention, 50Gi Longhorn storage, 2-4Gi memory
- **Grafana**: 10Gi persistent storage, dashboard auto-provisioning
- **Scraping**: k3s nodes (kubelet metrics) + ServiceMonitor discovery

### Loki Stack
- **Storage**: MinIO S3 backend with boltdb-shipper
- **Promtail**: Deployed as DaemonSet for log collection
- **Retention**: Configurable via storage policies

## Troubleshooting

### Common Issues & Solutions
1. **Longhorn Volume Degraded**: Check volume/replica status, delete failed replicas to trigger rebuilds
2. **Flux Sync Failures**: Use `flux get all -A` and `flux reconcile source git flux-system`
3. **Node Join Issues**: Verify k3s service status, node token, and firewall rules
4. **Storage Issues**: Monitor disk usage, clean up detached volumes and failed replicas
5. **Backup/Restore**: Use Longhorn CRDs to create/list backups programmatically

### Performance Tuning
```yaml
# /etc/rancher/k3s/config.yaml - Key optimizations
kube-proxy-arg: ["proxy-mode=ipvs", "ipvs-strict-arp=true"]
kubelet-arg: ["max-pods=250", "eviction-hard=memory.available<500Mi,nodefs.available<10%"]
```