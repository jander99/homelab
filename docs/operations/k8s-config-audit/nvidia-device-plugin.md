# nvidia-device-plugin (kube-system)

**Chart version:** 0.20.0 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Exposes GPU resources to the scheduler; a dependency of dcgm-exporter and tdarr (both already audited).

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `0.20.0` — confirmed current upstream latest, zero drift, no open Renovate PR needed.
- No `postRenderers` used at all — confirmed by reading `helmrelease.yaml` directly, so the dcgm-exporter-style silent-patch-mismatch failure mode cannot occur here.
- RBAC is minimal: single ClusterRole, `get/list/watch` on `nodes` only — no lease/coordination.k8s.io permissions at all, consistent with this component not leader-electing.
- `resources` comment in the HelmRelease is accurate, verified against the live pod: `nvidia-device-plugin-ctr` has requests/limits set exactly as declared (10m cpu / 100Mi mem request, 100Mi mem limit); `nvidia-device-plugin-sidecar` genuinely has `{}` (unbounded) on the live pod too — confirmed this is a real chart limitation (no resources templating for that container), not an oversight.
- `SYS_ADMIN` capability on both containers is justified — same category as dcgm-exporter/csi-driver-smb: device-plugin needs it for NVML/GPU driver access. `runtimeClassName: nvidia` is correctly required (documented in-repo: default runc runtime causes `ERROR_LIBRARY_NOT_FOUND`).
- The chart's `nvidia-device-plugin-mps-control-daemon` DaemonSet renders but is genuinely inert on this cluster — `DESIRED: 0/CURRENT: 0` live, because its `nodeSelector: nvidia.com/mps.capable=true` never matches this node (MPS isn't configured/enabled). Not dead config we introduced; harmless chart default, same pattern as MetalLB's idle frr-k8s BGP backend found earlier in this audit.
- Live pod: 0 restarts over 6d4h — completely stable.

### 🟡 Worth knowing, structurally hard to fix (upstream limitation)

No `securityContext` hardening beyond the two `SYS_ADMIN` capability adds — no `runAsNonRoot`, no `readOnlyRootFilesystem`, no dropped-capabilities baseline (pod-level `securityContext: {}`). Given `SYS_ADMIN` is already required, additional hardening here has limited practical value, but noting for completeness — matches the general pattern of GPU/host-privileged components in this audit lacking granular hardening options.

### Kine/leader-election pattern (issue #355) check

Not applicable. No lease RBAC, no leader-election flags in the rendered DaemonSet args, 0 restarts — this component cannot exhibit the pattern.

### 🔴 Clear actionable gaps

None found.
