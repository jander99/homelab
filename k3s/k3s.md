> **Current State (2026-05-02)**: This document describes the target GitOps architecture, not the current deployment. Today only a single-node K3s server is running on the testbed (`192.168.1.128`) using SQLite as the datastore. Flux CD, the Nx workspace, the CDK8s authoring layer, and HA embedded etcd are all future work. See `BOOTSTRAP.md` Part 1 for what is actually deployed, and Part 2 for the upgrade path.

---

# Homelab K3s GitOps Blueprint

This is the concrete repo blueprint for the planned K3s GitOps setup. It turns the earlier "Flux + CDK8s + Nx" direction into a specific filesystem layout, reconciliation graph, and bootstrap order.

## Decisions Locked In Now

These are the choices worth being opinionated about up front:

- **Monorepo**: cluster bootstrap, rendered manifests, and CDK8s source stay in this repo.
- **Flux consumes committed YAML only**: Flux watches `k3s/clusters/homelab/` specifically; it never watches the broader `k3s/` tree directly or TypeScript source.
- **CDK8s is the workload authoring layer**: application manifests are defined in TypeScript and rendered before commit.
- **Nx is orchestration, not truth**: Nx runs synth and validation locally or in CI, but the committed YAML is the deployment contract.
- **Single cluster root first**: start with `k3s/clusters/homelab/` and avoid `dev`/`staging` overlays until a second cluster exists.
- **Secrets use SOPS + age**: keep the decryption model simple and Flux-native.
- **Storage stays intentionally abstract**: keep shared constructs and manifests storage-class-light until a real CSI decision is needed.

## Target Cluster

- **Nodes**: 3x Dell Optiplex at `192.168.1.40`, `192.168.1.41`, `192.168.1.42`
- **Datastore**: embedded etcd once the cluster moves from single-node SQLite to HA
- **GitOps root**: `k3s/clusters/homelab/`
- **Ingress/TLS**: Nginx Ingress + cert-manager
- **Secrets**: SOPS + age
- **Storage posture**: do not hardcode a future storage vendor into the blueprint; only set `storageClassName` when a workload truly needs it

## Repository Blueprint

```text
homelab/
├── k3s/
│   ├── bootstrap/
│   │   └── ansible/
│   │       ├── inventory/
│   │       ├── playbooks/
│   │       └── roles/
│   ├── clusters/
│   │   └── homelab/
│   │       ├── flux-system/
│   │       │   ├── gotk-components.yaml
│   │       │   ├── gotk-sync.yaml
│   │       │   └── kustomization.yaml
│   │       ├── kustomization.yaml
│   │       ├── platform.yaml
│   │       ├── infra-controllers.yaml
│   │       ├── infra-configs.yaml
│   │       └── apps.yaml
│   ├── platform/
│   │   ├── namespaces/
│   │   │   ├── media.yaml
│   │   │   ├── observability.yaml
│   │   │   └── kustomization.yaml
│   │   ├── rbac/
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml
│   ├── infrastructure/
│   │   ├── controllers/
│   │   │   ├── cert-manager/
│   │   │   ├── ingress-nginx/
│   │   │   └── kustomization.yaml
│   │   ├── configs/
│   │   │   ├── cluster-issuers/
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml
│   └── applications/
│       ├── media/
│       ├── observability/
│       ├── networking/
│       └── kustomization.yaml
├── applications/
│   └── cdk8s/
│       ├── cdk8s.yaml
│       ├── package.json
│       ├── project.json
│       └── src/
│           ├── main.ts
│           ├── charts/
│           └── constructs/
├── nx.json
├── package.json
└── tsconfig.base.json
```

## Source-of-Truth Boundaries

Keep the boundaries strict:

- **Manual cluster plumbing lives in `k3s/platform/` and `k3s/infrastructure/`**.
- **Rendered workload manifests live in `k3s/applications/`**.
- **CDK8s source lives in `applications/cdk8s/src/`**.
- **Flux points only at `k3s/clusters/homelab/`**.
- **Nx points at the CDK8s workspace and writes rendered output into `k3s/applications/`**.

That means:

- Editing `applications/cdk8s/src/` changes the authoring layer.
- Running synth updates `k3s/applications/`.
- Flux reconciles only the committed output plus the manually managed platform and infrastructure layers.

## Flux Reconciliation Graph

Use one cluster root and a small, explicit dependency chain:

| Flux object | Path | Depends on | Purpose |
|-------------|------|------------|---------|
| `flux-system` | `./k3s/clusters/homelab/flux-system` | none | Flux controllers and source config |
| `platform` | `./k3s/platform` | `flux-system` | namespaces, RBAC, shared policies |
| `infra-controllers` | `./k3s/infrastructure/controllers` | `platform` | cert-manager, ingress-nginx, other controllers |
| `infra-configs` | `./k3s/infrastructure/configs` | `infra-controllers` | ClusterIssuers and controller-specific config |
| `apps` | `./k3s/applications` | `platform`, `infra-configs` | rendered workload manifests |

### Why this graph

- **`platform` first** so namespaces and shared RBAC exist before anything relies on them.
- **Controllers before configs** so CRDs and controller APIs exist before related resources are applied.
- **Applications last** so workloads only land after the cluster plumbing exists.

## CDK8s + Nx Workflow

Nx should stay thin and predictable. A single `cdk8s` project is enough to start.

### Suggested Nx Targets

| Target | Purpose | Notes |
|--------|---------|-------|
| `nx run cdk8s:synth` | render manifests | writes output into `k3s/applications/` |
| `nx run cdk8s:validate` | verify rendered tree | runs after synth; builds the cluster root with `kustomize` |
| `nx run cdk8s:diff` | review rendered changes | wrapper around `git diff -- k3s/applications` |

### Suggested `project.json` Shape

```json
{
  "name": "cdk8s",
  "targets": {
    "synth": {
      "command": "cd applications/cdk8s && cdk8s synth --output ../../k3s/applications"
    },
    "validate": {
      "dependsOn": ["synth"],
      "command": "kustomize build k3s/clusters/homelab >/dev/null"
    },
    "diff": {
      "dependsOn": ["synth"],
      "command": "git diff -- k3s/applications"
    }
  }
}
```

### Rendered Output Rules

- Commit both **source** and **rendered output** in the same change.
- Treat `k3s/applications/` as generated code: it is reviewable, committed, and reproducible.
- Do not hand-edit rendered manifests unless you are fixing generation immediately afterward.
- If a workload cannot yet be expressed cleanly in CDK8s, keep it as a manual manifest temporarily rather than weakening the Flux boundary.

## Secrets Strategy

Use SOPS from the beginning so the shape does not have to change later.

- Commit encrypted secrets as `*.sops.yaml`.
- Keep the age **private key out of Git**.
- Bootstrap Flux with the age decryption secret in `flux-system`.
- Store secrets near the layer that consumes them:
  - cluster-scoped secrets near `k3s/clusters/homelab/`
  - controller secrets near `k3s/infrastructure/`
  - application secrets near the rendered app manifests or their source inputs

## Minimal Bootstrap Sequence

This is the smallest useful path from today's single-node testbed to the planned GitOps shape:

1. **Bootstrap K3s with Ansible** using the existing `provision-nodes.yml` and `bootstrap-k3s.yml`.
2. **Create the cluster root** at `k3s/clusters/homelab/`.
3. **Bootstrap Flux** so it writes `flux-system/` into that cluster root and watches the `master` branch.
4. **Add the top-level Flux Kustomizations** for `platform`, `infra-controllers`, `infra-configs`, and `apps`.
5. **Generate an age key**, keep the private key outside Git, and wire Flux decryption before any real secret-bearing workloads land.
6. **Create the Nx + CDK8s workspace** under `applications/cdk8s/`.
7. **Render the first app manifests into `k3s/applications/`**, commit them, and let Flux reconcile them.
8. **Migrate services incrementally** once each workload has a GitOps-managed definition and a tested rollback path.

## Guardrails for Future Changes

These are the things to avoid because they are noisy or expensive to unwind later:

- **Do not add multi-environment overlays** until there is a second real cluster or environment.
- **Do not let Flux watch `applications/cdk8s/`** or run synth in-cluster.
- **Do not make shared constructs depend on a specific storage vendor**.
- **Do not mix cluster plumbing and application output in the same directory**.
- **Do not make Nx responsible for deployment state**; it is just the build and validation wrapper.
- **Do not hand-wave naming**: choose stable names for the cluster root, namespaces, and app folders early and keep them boring.

## Migration Notes

When Docker services move into K3s:

1. Define the workload in CDK8s when possible.
2. Render the manifest into `k3s/applications/`.
3. Keep persistence requirements explicit, but avoid product-specific storage assumptions in shared code.
4. Migrate one service at a time so Flux can re-apply everything if the cluster is rebuilt during the HA move.
