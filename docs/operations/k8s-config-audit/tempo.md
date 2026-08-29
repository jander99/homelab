# tempo (telemetry)

**Namespace:** telemetry
**Chart version:** 2.2.4 (drift to 2.3.0 already covered by open Renovate PR #338; appVersion unchanged at 2.10.8)
**Audit date:** 2026-08-28

Traces backend, single-binary mode. Receives OTLP traces from opentelemetry-collector (already audited) at `tempo.telemetry.svc.cluster.local:4317`.

## Findings

### 🟡 Worth knowing, partially fixable

- **Container-level `securityContext` is empty (`{}`)** — the chart exposes a real per-container knob (`securityContext.allowPrivilegeEscalation`/`capabilities.drop`/`readOnlyRootFilesystem`, all commented-out `{}` in the chart's own values.yaml) that isn't set in our HelmRelease, so it defaults to nothing. Pod-level `securityContext` *is* set (`runAsNonRoot: true`, `runAsUser/runAsGroup/fsGroup: 10001` — all chart defaults, not from our override) so the container already runs as non-root, but capability-dropping and `readOnlyRootFilesystem` are available and unused. Same category as the opentelemetry-collector finding: a real, fixable local gap, not an upstream limitation.
- **3 dead Service ports** (`tempo-zipkin` 9411, `tempo-otlp-legacy` 55680, `tempo-otlp-http-legacy` 55681) are exposed with no corresponding receiver ever configured — confirmed by rendering the actual `tempo.yaml` config: `distributor.receivers` only contains `jaeger` and `otlp`, never `zipkin` or the legacy OTLP ports. Unlike opentelemetry-collector's equivalent finding, **this chart offers no toggle to remove them** — the Service template hardcodes all these ports unconditionally, with no values-driven conditional. Not fixable without a postRenderer patch (and given the dcgm-exporter postRenderers-targeting bug found earlier in this audit, that path warrants extra care if ever attempted). Materially lower risk than the OTel collector's equivalent finding though: this Service is `ClusterIP` only, not `hostPort`, so it's reachable only from inside the cluster network, not the LAN.
- **`jaeger` receiver ports (14250/6832/6831/14268) are real, live listeners, just currently unused** — opentelemetry-collector only sends OTLP-format traces, not Jaeger-format. Unlike zipkin/otlp-legacy, this one *is* fixable: `tempo.receivers` is a genuine values override key — setting it to `{otlp: {...}}` only (dropping the `jaeger` block) would disable this at the actual config/listener level, not just hide a Service port. Low priority: the current setup works and Jaeger support costs little on a single-binary process with no separate resource footprint per receiver.

### 🟢 Well-configured, no action needed

- Chart pinned at `2.2.4`; drift to `2.3.0` (minor) is already covered by open Renovate PR #338 (bundled with alloy/loki/opentelemetry-collector) — appVersion stays `2.10.8` either way, so this is a chart-templating-only bump, not a binary change.
- **No RBAC at all** — confirmed via full chart render: no ClusterRole/Role/Binding of any kind. Tempo doesn't watch the Kubernetes API, so it needs none — tightest possible posture, better than every other component audited this session.
- Single-binary mode is genuinely the chart's *only* topology ("Grafana Tempo Single Binary Mode" — architecturally a different, dedicated chart from `tempo-distributed`, not a mode toggle within one chart), so there's no unnecessary-replica-count risk here the way there was with longhorn's CSI sidecars (issue #356) — `replicas: 1` is hardcoded, not a value that could even be misconfigured.
- Resource requests/limits set and match the live StatefulSet exactly; CPU limit deliberately unset (documented rationale, same Go-runtime convention as elsewhere in this repo).
- `livenessProbe`/`readinessProbe` both present and correctly configured (`/ready` on port 3200).
- **Ingest path confirmed genuinely wired end-to-end**: live Service exposes `grpc-tempo-otlp` on port 4317, matching exactly what opentelemetry-collector's audit found it configured to dial (`tempo.telemetry.svc.cluster.local:4317`) — not a dangling reference.
- Storage backend is local disk (`backend: local`, `local-path` StorageClass, 5Gi PVC) with a documented rationale (7 days of homelab-scale trace volume) — reasonable for this cluster's scale, no unnecessary object-storage complexity.
- Live pod: **0 restarts over 6d4h** — completely stable.

### Kine/leader-election pattern (issue #355) check

Not applicable and not present. No RBAC means no lease permissions of any kind; 0 restarts confirms no instability. Does not land in or near the 2026-08-28 ~22:20 UTC cascade window.

### 🔴 Clear actionable gaps

None found.
