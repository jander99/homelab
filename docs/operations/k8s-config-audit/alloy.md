# alloy (telemetry)

**Namespace:** telemetry
**Chart version:** 1.11.1 (grafana/alloy)
**Pinned image tag:** v1.18.1
**Audit date:** 2026-08-28

Grafana Alloy, deployed as a DaemonSet, tailing pod logs via the Kubernetes API (not host mounts) and shipping them to Loki.

## Findings

### 🟢 Well-configured, no action needed

- Pod security context is genuinely hardened: `runAsNonRoot`, UID/GID 65534, `readOnlyRootFilesystem: true`, all capabilities dropped, seccomp `RuntimeDefault` — on both the alloy container and the `config-reloader` sidecar.
- Resource limits set with a documented rationale (CPU limit deliberately omitted for a Go runtime — reasonable, avoids CFS throttling stalls).
- `readinessProbe` present and correct.
- Service is `ClusterIP` only — nothing unnecessarily exposed.
- Deliberately avoids host mounts (`/var/log`, `/var/lib` disabled) by using the Kubernetes-API log-tailing mode instead — smaller footprint than the conventional Alloy/Promtail DaemonSet pattern.
- Image tag pinned explicitly and matched to chart `appVersion`, with a comment explaining why (protects against chart-bump/binary-version drift).
- Chart version drift (1.11.1 → 1.12.1) is already queued — Renovate PR #338 is open and covers this along with loki/tempo/opentelemetry-collector bumps. Not a gap, just not-yet-merged.

### 🟡 Worth knowing, not clearly actionable

- **No `livenessProbe`** — only `readinessProbe`. This is the upstream chart's own default (verified by rendering the actual chart templates), not something introduced here. Low real-world impact for a DaemonSet log-shipper with no upstream traffic depending on it, but means a wedged (not crashed) Alloy process wouldn't self-heal via kubelet restart.
- **ClusterRole is upstream's "kitchen sink" RBAC**, not scoped to what this specific config actually uses. Our Alloy config only does `discovery.kubernetes "pods"` + `loki.source.kubernetes` (needs `pods`, `pods/log`, `namespaces` get/list/watch), but the chart's single shared ClusterRole additionally grants cluster-wide get/list/watch on `secrets`, `configmaps`, `services`, `endpoints`, `ingresses`, `nodes`, `events`, `replicasets`, plus watch access to several Prometheus-Operator CRDs (`servicemonitors`, `podmonitors`, `prometheusrules`, etc.) — none of which this pipeline touches. This is inherent to the chart (no values.yaml knob to shrink it) and would require hand-writing a replacement ClusterRole to fix, which breaks the "just consume the chart" model. Flagging as a real but structurally-hard-to-fix gap: if this pod were ever compromised, the blast radius includes cluster-wide Secret reads, not just log access.
- **No NetworkPolicy** — true for every namespace in this repo except Flux's own vendored bootstrap resources. Could not reliably confirm from this shell whether the cluster's k3s flannel install actually enforces NetworkPolicy (no `--disable-network-policy` flag in the ansible role, so it likely is enforced by default) — this is a repo-wide pattern, not alloy-specific, so it's noted once here rather than repeated per-component.

### 🔴 Clear actionable gaps

None found for alloy.
