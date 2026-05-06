# K3S DIRECTORY

## OVERVIEW
**K3s bootstrap is implemented; Flux CD v2 GitOps is scaffolded with real infrastructure manifests deployed.** Ansible provisions OS and installs K3s single-node. Flux is bootstrapped with Kustomizations committed — infrastructure controllers (cert-manager, metallb) and headlamp application are deployed. CDK8s/Nx workspace is initialized but contains only a stub chart; manifest promotion workflow is not yet designed.

## WHAT EXISTS
```
k3s/
├── k3s.md                    # Architecture docs: Flux graph, CDK8s/Nx blueprint, networking
├── BOOTSTRAP.md              # Step-by-step bootstrap guide
├── bootstrap/ansible/        # ✓ Implemented — see bootstrap/ansible/AGENTS.md
├── clusters/homelab/         # ✓ Flux Kustomization manifests committed
│   ├── flux-system/            # gotk-components, gotk-sync, kustomization.yaml
│   └── *.yaml                  # 5x Kustomization CRs (platform → infra-controllers → infra-configs → apps)
├── platform/                 # ✓ kustomization.yaml + namespaces/ (cert-manager, headlamp, pihole)
├── infrastructure/
│   ├── controllers/            # ✓ cert-manager + metallb HelmReleases — see infrastructure/AGENTS.md
│   └── configs/                # ✓ ClusterIssuers + IPAddressPool + SOPS-encrypted Cloudflare token
└── applications/             # ✓ headlamp HelmRelease deployed (headlamp.homelab.properties)
```

> Last verified: 2026-05-05

## LAYER STATUS
| Component | Location | Status |
|-----------|----------|--------|
| Ansible playbooks | `k3s/bootstrap/ansible/` | ✓ provision-nodes + bootstrap-k3s runnable |
| Flux cluster root | `k3s/clusters/homelab/` | ✓ Kustomizations committed (Flux v2.3.0) |
| Platform manifests | `k3s/platform/` | ✓ Namespace manifests (cert-manager, headlamp, pihole) |
| Infrastructure manifests | `k3s/infrastructure/` | ✓ Implemented — cert-manager + metallb controllers + configs |
| CDK8s TypeScript | `applications/cdk8s/src/` | ✓ HelloChart stub (creates hello-cdk8s namespace only) |
| Application manifests | `k3s/applications/` | ✓ Headlamp deployed via Flux (headlamp.homelab.properties) |
| Nx orchestration | `nx.json`, `project.json` | ✓ Workspace initialized; synth target configured (Yarn 4.14.1) |
| SOPS secrets | `.sops.yaml` | ✓ Created (age key encryption) |

## TARGET CLUSTER
- **Nodes**: 3x Dell Optiplex at 192.168.1.40, 192.168.1.41, 192.168.1.42
- **Datastore**: embedded etcd after the HA rebuild
- **GitOps**: Flux CD v2 watching this repo (`master` branch) via `k3s/clusters/homelab/`
- **Authoring**: Nx + CDK8s render workload manifests into `k3s/applications/`
- **Ingress**: Traefik + cert-manager (Let's Encrypt)
- **Secrets**: SOPS + age key encryption
- **Storage**: keep manifests storage-class-light until a real CSI decision is made

## ANTI-PATTERNS
- **Do not create files here expecting them to be deployed** — the K3s cluster may not exist yet.
- **Do not treat `k3s.md` as current state** — it describes the target, not reality.
- **Do not describe CDK8s as unimplemented** — HelloChart stub exists at `applications/cdk8s/src/main.ts`. Nx workspace is initialized. What's missing is real workloads and the dist/ → k3s/applications/ promotion workflow.
- **Do not hardcode a speculative storage vendor into new planning docs unless the repo actually adopts one.**
- **Do not run `ansible-playbook` commands from `BOOTSTRAP.md`** without verifying nodes are provisioned.

## NOTES
- `BOOTSTRAP.md` is the authoritative guide for standing up the cluster when ready.
- `k3s.md` contains the concrete repo blueprint, Flux kustomization graph, and Nx/CDK8s workflow.
- Current Docker services on Synology NAS are the live production environment — K3s migration is future work.
- **Testbed node** (i7-4770k) at 192.168.1.128 is the first node to provision. Re-IP to 192.168.1.4x before joining the cluster.
- `provision-nodes.yml` is runnable — runs `common` + `k3s-prereqs` roles.
- `bootstrap-k3s.yml` is runnable — runs `k3s-server` role to install and configure a single K3s server node.
- `bootstrap-flux.yml` is a stub Ansible playbook — Flux was bootstrapped manually; manifests live in `k3s/clusters/homelab/`.
- `group_vars/` lives at `inventory/group_vars/all.yml` (not at the ansible root) — required for `ansible-playbook` variable loading to work correctly.
