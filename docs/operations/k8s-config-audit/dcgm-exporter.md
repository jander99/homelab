# dcgm-exporter (kube-system)

**Namespace:** kube-system
**Chart version:** 4.8.3 — current upstream latest, zero drift
**Audit date:** 2026-08-28

NVIDIA DCGM Exporter, exposing GPU metrics for Prometheus scraping.

## Findings

### 🔴 Clear actionable gap — confirmed via direct reproduction, not upstream-inherited

**The HelmRelease's `postRenderers` Kustomize patch has never actually applied, since it was introduced.** `helmrelease.yaml` targets the patch at `kind: DaemonSet, name: dcgm-exporter`, but the chart (with Helm release name `kube-system-dcgm-exporter`) actually renders the DaemonSet as `kube-system-dcgm-exporter` — the release-name prefix is included. The patch target name doesn't match anything, so Kustomize silently no-ops.

Confirmed independently (not just by the research agent) against both the rendered chart and the live cluster:
- `helm template` with our values renders a DaemonSet named `kube-system-dcgm-exporter`, not `dcgm-exporter`.
- Live pod: `livenessProbe.initialDelaySeconds: 45` (patch claims to set `0`), `resources.limits.cpu: 200m` still present (patch has an explicit `remove` op for this path), no `startupProbe` present at all (patch claims to add one).
- HelmRelease reports `Ready`/`UpgradeSucceeded` — Flux has no way to know the postRenderer silently matched nothing; there's no error surfaced anywhere.

This means PRs #256 and #257 — which specifically set out to fix probe timing and adopt `postRenderers` for it — have not actually been in effect for the ~14+ days since the last Helm upgrade, despite being merged and believed to be working.

**Fix:** change the patch target to `name: kube-system-dcgm-exporter`, or switch to a label selector (e.g. `app.kubernetes.io/name: dcgm-exporter`) that's robust to Helm release-name prefixing regardless of release name.

**Scope note, not yet investigated:** commit `48ed3c7` applied this same postRenderers-probe-patch pattern to `pihole`, `portainer`, and `tdarr-node` in one PR alongside dcgm-exporter. Those components haven't been audited yet in this series — worth specifically checking their patch targets against their actual rendered resource names when they come up, since this exact mismatch could be silently present in up to three more places.

### 🟢 Well-configured, no action needed

- Chart already at latest version (`4.8.3`) — no drift.
- RBAC is excellent: single Role, `get`-only on one named ConfigMap (`exporter-metrics-config-map`). Tightest RBAC of any component audited so far.
- Resource requests/limits (memory) are krr-tuned with a documented rationale (539Mi P95 usage → 540Mi request/limit), and the CPU-limit-removal rationale is well-explained even though the mechanism to actually apply it is broken (see 🔴 above).
- `SYS_ADMIN` capability + `runAsUser: 0` is justified: DCGM needs this for NVML/GPU driver access — standard, unavoidable pattern for GPU metrics exporters, same category as other host-privileged components audited earlier (system-upgrade-controller Jobs, csi-driver-smb).
- No leader election — not a candidate for the kine/SQLite lease-contention issue (#355). 0 restarts / 14 days confirms no instability of any kind.

### 🟡 Worth knowing, structurally hard to fix

None beyond the GPU-privilege note above, which is justified rather than a gap.
