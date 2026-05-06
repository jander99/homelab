# CDK8S DIRECTORY

**Generated:** 2026-05-05

## OVERVIEW

CDK8s TypeScript application for generating Kubernetes manifests. Currently a **stub** — `main.ts` contains only a `HelloChart` that creates the `hello-cdk8s` namespace. The Nx `synth` target is configured and cached. Output in `dist/` is gitignored and not yet wired into `k3s/applications/`.

## STATUS

| Component | Status |
|-----------|--------|
| Nx workspace | ✓ Initialized (`nx.json`, `package.json`, Yarn 4.14.1) |
| CDK8s project | ✓ Scaffolded (`cdk8s.yaml`, `project.json`, `tsconfig.json`) |
| `synth` Nx target | ✓ Configured + cached |
| `main.ts` | ✓ HelloChart stub (creates `hello-cdk8s` namespace only) |
| Real workload manifests | ❌ Not implemented |
| Wired to `k3s/applications/` | ❌ Not implemented |

## STRUCTURE

```
cdk8s/
├── src/
│   └── main.ts         # HelloChart stub — creates hello-cdk8s namespace only
├── dist/               # Synthesized YAML output (gitignored)
│   └── hello.k8s.yaml
├── cdk8s.yaml          # CDK8s app config
├── package.json        # CDK8s + constructs dependencies
├── project.json        # Nx project config (defines synth target)
└── tsconfig.json       # TypeScript config (inherits tsconfig.base.json)
```

## INTENDED WORKFLOW (future state)

1. Author workloads as CDK8s constructs in `src/main.ts`
2. Run `nx run cdk8s:synth` — synthesizes YAML to `dist/`
3. Copy/promote manifests from `dist/` into `k3s/applications/`
4. Commit to `master` — Flux picks up `k3s/applications/` and applies to cluster

The promotion step (dist/ → k3s/applications/) is not yet designed. See `.sisyphus/plans/nx-cdk8s-init.md` for planning notes.

## COMMANDS

```bash
# From repo root:
yarn nx run cdk8s:synth

# Or from this directory:
yarn cdk8s synth
```

## ANTI-PATTERNS

- **Do not add real workloads to `main.ts`** until the CDK8s ↔ `k3s/applications/` promotion workflow is designed and documented.
- **Do not commit `dist/` output** — it is gitignored (`applications/cdk8s/dist/`). Manifests go to `k3s/applications/` instead.
- **Do not import CDK8s constructs** before running `cdk8s import` — generated imports go to `applications/cdk8s/imports/` (also gitignored).
- **Do not describe HelloChart as a deployed workload** — it is a scaffolding stub only.
