# node-feature-discovery (node-feature-discovery)

**Chart version:** 0.19.0 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Labels nodes with hardware/kernel/feature info; a real, actively-used dependency for GPU-aware scheduling on this cluster.

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `0.19.0` — confirmed current upstream latest, zero drift, no Renovate PR needed.
- RBAC is properly scoped per-component: master's ClusterRole is limited to `namespaces` watch/list, `nodes`/`nodes/status` get/patch/update/list, NFD's own CRDs, and lease management restricted via `resourceNames` to exactly one named lease (`nfd-master.nfd.kubernetes.io`); gc's ClusterRole is even tighter (nodes list/watch, `noderesourcetopologies`/`nodefeatures` delete/list); worker only gets a namespaced Role (`nodefeatures` CRUD + `pods` get). No over-grants.
- All three workload types (worker DaemonSet, master Deployment, gc Deployment) are fully hardened: `runAsNonRoot`, all capabilities dropped, `readOnlyRootFilesystem: true`, no privilege escalation — and all have complete liveness/readiness probes (master also has a startupProbe).
- Resource requests/limits are explicitly tuned via krr with a documented rationale (chart's own unbounded 512Mi default was ~5x oversized; pinned to 10m/100Mi observed usage), matching this repo's established convention.
- master and gc already run 1 replica each — no unnecessary-replica lease-churn problem here (unlike the longhorn finding in issue #356).
- **NFD's node labels are a genuine, actively-satisfied dependency, not redundant on this single-node cluster** — confirmed directly: `nvidia-device-plugin`'s *live* DaemonSet carries a real `nodeAffinity` (chart default, not set in our values override) with `feature.node.kubernetes.io/pci-10de.present=true` as one of three OR'd match terms, and NFD is confirmed producing that exact label on the node right now. Not dead config.

### 🟡 Worth knowing, not actionable — two distinct historical crash events, neither is the kine pattern

- All 3 pods' restarts were checked against `container lastState` (`exitCode`/`reason`/`finishedAt`), not just counts. **None show the kine/leader-election signature** (`context deadline exceeded` on a lease PUT) despite master genuinely holding lease RBAC — a true negative, not an unchecked gap.
- master + gc restarted simultaneously at `2026-08-08T01:20:33Z`, both `exitCode: 255, reason: Unknown` — a node/containerd-level event roughly 3 weeks before this audit, unrelated to both the kine cascade and the more recent k3s upgrade. Too old to matter operationally.
- worker restarted once at `2026-08-28T17:22:24Z`, same `exitCode: 255, reason: Unknown` signature — lines up with the k3s v1.36.3→v1.36.4 auto-upgrade window from earlier in this session (reflector watch errors were logged at `17:22:17Z` that same day) and matches the identical crash signature already seen on `external-dns` (also `exitCode=255`/`Unknown`, also attributed to a node-level container-runtime disruption). Confirms this specific exit signature is a distinct, recognizable "node/runtime restart" fingerprint, separate from the kine lease-timeout fingerprint (`context deadline exceeded` on a lease PUT) — useful to keep both fingerprints distinct for the rest of this audit rather than lumping all restarts together.

### Kine/leader-election pattern (issue #355) check

Not present — checked directly via exit reasons on all 3 pods, not just restart counts.

### 🔴 Clear actionable gaps

None found.
