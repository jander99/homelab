# INFRASTRUCTURE DIRECTORY

**Generated:** 2026-05-05

## OVERVIEW

Flux-managed infrastructure layer split into two reconciliation stages:
- **controllers/**: HelmRelease + HelmRepository manifests that install cluster controllers and their CRDs.
- **configs/**: Supporting resources (ClusterIssuers, IPAddressPools, SOPS-encrypted secrets) that depend on those CRDs existing first.

## STRUCTURE

```
infrastructure/
├── controllers/
│   ├── cert-manager/   # helmrelease.yaml, helmrepository.yaml, kustomization.yaml
│   └── metallb/        # helmrelease.yaml, helmrepository.yaml, kustomization.yaml
└── configs/
    ├── cert-manager/   # cloudflare-token.sops.yaml, clusterissuer-{prod,staging}.yaml, kustomization.yaml
    └── metallb/        # ipaddresspool.yaml, l2advertisement.yaml, kustomization.yaml
```

## RECONCILIATION ORDER

Flux Kustomization `infra-configs` has `dependsOn: [infra-controllers]`. This guarantees HelmReleases (and their CRDs) install before ClusterIssuers or IPAddressPools are applied. Do not bypass this ordering.

## WHAT'S DEPLOYED

### cert-manager
- **Chart**: `jetstack/cert-manager` `>=1.14.0 <2.0.0` | namespace: `cert-manager`
- **CRDs**: `crds.enabled: true`, policy: `CreateReplace` on install and upgrade
- **Issuers**: `letsencrypt-prod` and `letsencrypt-staging` ClusterIssuers (Cloudflare DNS-01 challenge)
- **Secret**: `cloudflare-token.sops.yaml` — SOPS age-encrypted Cloudflare API token; Flux decrypts via `flux-system/sops-age` Secret in cluster

### metallb
- **Chart**: `metallb` from metallb Helm repository | namespace: `metallb-system`
- **IPAddressPool**: defined in `configs/metallb/ipaddresspool.yaml`
- **L2Advertisement**: defined in `configs/metallb/l2advertisement.yaml`

### Headlamp (reference — lives in `k3s/applications/headlamp/`)
- Uses `cert-manager.io/cluster-issuer: letsencrypt-prod` in Traefik ingress
- URL: `headlamp.homelab.properties`

## WHERE TO LOOK

| Task | File |
|------|------|
| Add a new controller chart | `controllers/<name>/helmrelease.yaml` + `helmrepository.yaml` + `kustomization.yaml` |
| Add a ClusterIssuer | `configs/cert-manager/` |
| Change IP address pool | `configs/metallb/ipaddresspool.yaml` |
| Edit Cloudflare token secret | `configs/cert-manager/cloudflare-token.sops.yaml` via `sops` CLI |

## ANTI-PATTERNS

- **Do not hand-edit `cloudflare-token.sops.yaml`** — SOPS-encrypted; edit only with `sops cloudflare-token.sops.yaml` using the age key at `~/.kube/k3s-homelab-age.agekey`.
- **Do not add configs/ resources that need CRDs from controllers/** without ensuring `infra-configs` dependsOn remains correct.
- **Do not duplicate ClusterIssuers** — `letsencrypt-prod` and `letsencrypt-staging` already exist; reference by name in ingress annotations.
- **Do not add a new controller without a matching entry** in the `infra-controllers` Kustomization's `resources:` list at `k3s/clusters/homelab/infra-controllers.yaml`.

## NOTES

- `cloudflare-token.sops.yaml.example` is an unencrypted reference template — safe to read/edit.
- The age key fingerprint is in `.sops.yaml` at the repo root. The private key is **not** in git; it lives at `~/.kube/k3s-homelab-age.agekey` on the Ansible controller and as `flux-system/sops-age` Secret in the cluster.
- cert-manager's `HelmRelease` uses `helm.toolkit.fluxcd.io/v2` API (Flux v2.3.0 compatible).
