# K3S DIRECTORY

## OVERVIEW
**Single-node K3s bootstrap is implemented.** Ansible provisions OS nodes and installs the K3s server role. Flux CD, the Nx workspace, and the CDK8s authoring layer remain unimplemented — see Part 2 of `BOOTSTRAP.md` for the upgrade path.

## WHAT EXISTS
```
k3s/
├── k3s.md          # Architecture docs: Flux graph, CDK8s/Nx blueprint, networking
├── BOOTSTRAP.md    # Step-by-step bootstrap guide: Ansible playbooks, inventory, K3s install
└── bootstrap/ansible/   # ✅ Initialized — OS provisioning for testbed (192.168.1.128)
    ├── ansible.cfg
    ├── inventory/hosts.yml      # Testbed node; add cluster nodes here
    ├── inventory/group_vars/all.yml  # Common vars: packages, UFW rules, kernel modules
    ├── playbooks/
    │   ├── provision-nodes.yml  # OS hardening + K3s prereqs (runnable now)
    │   ├── bootstrap-k3s.yml    # K3s server install (runnable; uses k3s-server role)
    │   ├── bootstrap-flux.yml   # Flux CD stub (not yet runnable)
    │   └── site.yml             # Full entrypoint (runs all phases)
    ├── roles/
        ├── common/              # apt upgrade, packages, timezone, UFW, passwordless sudo; asserts vars non-empty
        ├── k3s-prereqs/         # swap disable, kernel modules, sysctl
        └── k3s-server/          # K3s server install, config, kubeconfig fetch, token persistence
```

> Last verified: 2026-05-02

## PLANNED ARCHITECTURE (not yet created)
| Component | Planned Location | Status |
|-----------|-----------------|--------|
| Ansible playbooks | `k3s/bootstrap/ansible/` | ✅ Initialized (provision-nodes, bootstrap-k3s runnable) |
| Flux cluster root | `k3s/clusters/homelab/` | ❌ Not created |
| Platform manifests | `k3s/platform/` | ❌ Not created |
| Infrastructure manifests | `k3s/infrastructure/` | ❌ Not created |
| CDK8s TypeScript | `applications/cdk8s/src/` | ❌ Not created |
| Rendered application manifests | `k3s/applications/` | ❌ Not created |
| Nx orchestration | `nx.json`, `applications/cdk8s/project.json` | ❌ Not created |
| SOPS secrets | `*.sops.yaml` files | ❌ Not created |

## TARGET CLUSTER
- **Nodes**: 3x Dell Optiplex at 192.168.1.40, 192.168.1.41, 192.168.1.42
- **Datastore**: embedded etcd after the HA rebuild
- **GitOps**: Flux CD v2 watching this repo (`master` branch) via `k3s/clusters/homelab/`
- **Authoring**: Nx + CDK8s render workload manifests into `k3s/applications/`
- **Ingress**: Nginx + cert-manager (Let's Encrypt)
- **Secrets**: SOPS + age key encryption
- **Storage**: keep manifests storage-class-light until a real CSI decision is made

## ANTI-PATTERNS
- **Do not create files here expecting them to be deployed** — the K3s cluster may not exist yet.
- **Do not treat `k3s.md` as current state** — it describes the target, not reality.
- **Do not describe planned components as implemented** — Flux, Nx/CDK8s, and HA are future state only.
- **Do not hardcode a speculative storage vendor into new planning docs unless the repo actually adopts one.**
- **Do not run `ansible-playbook` commands from `BOOTSTRAP.md`** without verifying nodes are provisioned.

## NOTES
- `BOOTSTRAP.md` is the authoritative guide for standing up the cluster when ready.
- `k3s.md` contains the concrete repo blueprint, Flux kustomization graph, and Nx/CDK8s workflow.
- Current Docker services on Synology NAS are the live production environment — K3s migration is future work.
- **Testbed node** (i7-4770k) at 192.168.1.128 is the first node to provision. Re-IP to 192.168.1.4x before joining the cluster.
- `provision-nodes.yml` is runnable — runs `common` + `k3s-prereqs` roles.
- `bootstrap-k3s.yml` is runnable — runs `k3s-server` role to install and configure a single K3s server node.
- `bootstrap-flux.yml` is a stub — Flux CD bootstrap is not yet implemented.
- `group_vars/` lives at `inventory/group_vars/all.yml` (not at the ansible root) — required for `ansible-playbook` variable loading to work correctly.
