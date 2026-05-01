# K3S DIRECTORY

## OVERVIEW
**Partially implemented.** Ansible directory is initialized for OS provisioning. K3s install, Flux CD, and CDK8s remain unimplemented.

## WHAT EXISTS
```
k3s/
├── k3s.md          # Architecture docs: CDK8s constructs, Flux structure, networking (186 lines)
├── BOOTSTRAP.md    # Step-by-step bootstrap guide: Ansible playbooks, inventory, K3s install (805 lines)
└── bootstrap/ansible/   # ✅ Initialized — OS provisioning for testbed (192.168.1.128)
    ├── ansible.cfg
    ├── inventory/hosts.yml      # Testbed node; add cluster nodes here
    ├── inventory/group_vars/all.yml  # Common vars: packages, UFW rules, kernel modules
    ├── playbooks/
    │   ├── provision-nodes.yml  # OS hardening + K3s prereqs (runnable now)
    │   ├── bootstrap-k3s.yml    # K3s install stub (not yet runnable)
    │   ├── bootstrap-flux.yml   # Flux CD stub (not yet runnable)
    │   └── site.yml             # Full entrypoint (runs all phases)
    └── roles/
        ├── common/              # apt upgrade, packages, timezone, UFW, passwordless sudo; asserts vars non-empty
        └── k3s-prereqs/         # swap disable, kernel modules, sysctl
```

## PLANNED ARCHITECTURE (not yet created)
| Component | Planned Location | Status |
|-----------|-----------------|--------|
| Ansible playbooks | `k3s/bootstrap/ansible/` | ✅ Initialized (provision-nodes only) |
| Flux CD configs | `k3s/clusters/`, `k3s/infrastructure/` | ❌ Not created |
| CDK8s TypeScript | `applications/cdk8s/src/` | ❌ Not created |
| Generated manifests | `applications/cdk8s/manifests/` | ❌ Not created |
| SOPS secrets | `*.sops.yaml` files | ❌ Not created |
| Longhorn storage | K3s manifests | ❌ Not created |

## TARGET CLUSTER
- **Nodes**: 3x Dell Optiplex at 192.168.1.40, 192.168.1.41, 192.168.1.42
- **Storage**: Longhorn on `/dev/nvme0n1`, 3-way replication
- **GitOps**: Flux CD v2 watching this repo (`master` branch)
- **Ingress**: Nginx + cert-manager (Let's Encrypt)
- **Secrets**: SOPS + age key encryption

## ANTI-PATTERNS
- **Do not create files here expecting them to be deployed** — the K3s cluster may not exist yet.
- **Do not treat `k3s.md` as current state** — it describes the target, not reality.
- **Do not run `ansible-playbook` commands from `BOOTSTRAP.md`** without verifying nodes are provisioned.

## NOTES
- `BOOTSTRAP.md` is the authoritative guide for standing up the cluster when ready.
- `k3s.md` contains CDK8s TypeScript construct API and Flux kustomization patterns.
- Current Docker services on Synology NAS are the live production environment — K3s migration is future work.
- **Testbed node** (i7-4770k) at 192.168.1.128 is the first node to provision. Re-IP to 192.168.1.4x before joining the cluster.
- `provision-nodes.yml` is the only runnable playbook today — runs `common` + `k3s-prereqs` roles.
- `bootstrap-k3s.yml` and `bootstrap-flux.yml` are stubs; K3s server role (`roles/k3s-server/`) does not yet exist.
- `group_vars/` lives at `inventory/group_vars/all.yml` (not at the ansible root) — required for `ansible-playbook` variable loading to work correctly.
