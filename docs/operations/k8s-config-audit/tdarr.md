# tdarr (media)

**Audit date:** 2026-08-28

Raw Deployment manifests (no Helm chart) — GPU-accelerated media transcoding, split into `tdarr-server` (coordinator) and `tdarr-node` (transcode worker).

## Findings

### 🔴 Clear actionable gap

- Both deployments implicitly use the `default` ServiceAccount (empty `serviceAccountName`) with no `automountServiceAccountToken: false`. Neither container ever calls the Kubernetes API, so a default API token is being mounted into every tdarr pod for no reason. Free, no-downside fix: set `automountServiceAccountToken: false` on both Deployments (or better, a minimal dedicated ServiceAccount with no RBAC bindings).

### 🟢 Well-configured, no action needed

- Image tags pinned explicitly (`2.86.01` on both `tdarr-node`/`tdarr-server`), confirmed against Docker Hub to be the actual latest published tag (98 tags checked, sorted) — zero drift, consistent with no open Renovate PR touching it.
- GPU access uses the clean Kubernetes device-plugin pattern (`runtimeClassName: nvidia` + `resources.limits.nvidia.com/gpu: "1"`), not raw host/privileged device access — better-scoped than the host-privilege patterns seen elsewhere in this audit (dcgm-exporter, csi-driver-smb).
- The direct-manifest probe-timing fix from PR #256 genuinely took effect: live pod's `startupProbe`/`livenessProbe` values match git exactly. This is the good counterexample to dcgm-exporter's silently-broken Helm `postRenderers` patch — no Helm involved here, so that specific failure mode can't occur, and it didn't.
- Exec-based probes (`pgrep -f 'node.*Tdarr_Node'`) are a reasonable, documented substitute since `tdarr_node` exposes no HTTP port.
- Resource requests/limits set on both deployments with sensible headroom for a GPU transcode workload.
- Storage is coherent: PVCs correctly migrated to Longhorn (documented migration path in comments), SMB-backed shared media PV references CSI credentials by secret ref, not hardcoded.
- Ingress uses cert-manager + traefik consistent with the rest of the repo.
- 0 restarts on both pods over 6+ days.

### 🟡 Worth knowing, plausibly justified but not confirmed

- Container-level `securityContext` is completely empty on both containers (only pod-level `fsGroup: 100` set) — no `runAsNonRoot`, no dropped capabilities, no `readOnlyRootFilesystem`. The `PUID`/`PGID` env vars strongly suggest a LinuxServer.io-style entrypoint that starts as root to chown volumes before dropping privileges internally, which would make `runAsNonRoot: true` break container startup — but this wasn't verified against the actual image entrypoint/Dockerfile, so it's a plausible constraint, not a settled one. `allowPrivilegeEscalation: false` and `seccompProfile: RuntimeDefault` are likely safe to add regardless and worth a follow-up look.
- `NVIDIA_DRIVER_CAPABILITIES=all`/`NVIDIA_VISIBLE_DEVICES=all` on tdarr-node are legacy nvidia-container-runtime env vars, likely redundant now that GPU access goes through the device-plugin resource limit — probably harmless, not worth a dedicated fix.
- No NetworkPolicy (repo-wide pattern, not tdarr-specific).

### Kine/leader-election pattern (issue #355) check

Not applicable — tdarr is an application, not a controller, and doesn't leader-elect.
