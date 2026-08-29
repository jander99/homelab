# opentelemetry-collector (telemetry)

**Namespace:** telemetry
**Chart version:** 0.170.0 (drift to 0.172.0 already covered by open Renovate PR #338)
**Audit date:** 2026-08-28

Daemonset-mode OTel Collector; traces feed Tempo, logs/metrics currently route to a `debug` exporter placeholder (documented, intentional gap pending a Prometheus pipeline).

## Findings

### 🔴 Clear actionable gaps

1. **No `securityContext`/`podSecurityContext` set at all (renders as `{}` at both pod and container level)** — unlike alloy/portainer/pihole (where the chart genuinely has no knob), this chart *does* expose both `podSecurityContext` and `securityContext` values keys (confirmed via `helm show values`, both default `{}`). This is a real, fixable local gap, not an upstream limitation — every other well-hardened component in this repo (alloy, cert-manager, external-dns, flux2, node-feature-discovery) sets the same standard block (`runAsNonRoot`, drop all capabilities, `readOnlyRootFilesystem`, seccomp `RuntimeDefault`) and this component should too.

2. **4 unused host-network ports are exposed unnecessarily**: `jaeger-compact` (6831/UDP), `jaeger-thrift` (14268/TCP), `jaeger-grpc` (14250/TCP), `zipkin` (9411/TCP) — all bound as `hostPort` on the node (confirmed `hostNetwork: false`, so these are real host-level port bindings via kube-proxy, reachable from the LAN, not just cluster-internal). Confirmed via the rendered config's `service.pipelines` block that **none of the 3 active pipelines (logs/metrics/traces) reference the `jaeger` or `zipkin` receivers** — only `otlp`, `prometheus`, `hostmetrics`, `kubeletstats`, `k8s_cluster` are wired in. These receivers are chart defaults that our custom `config.receivers` block can't remove (Helm merges, doesn't replace), but the chart exposes a separate, purpose-built toggle for exactly this: `ports.jaeger-compact.enabled`, `ports.jaeger-thrift.enabled`, `ports.jaeger-grpc.enabled`, `ports.zipkin.enabled` (all default `true`, confirmed present in `helm show values`). Setting all four to `false` removes the dead host-port exposure cleanly with zero functional impact. The `otlp`/`otlp-http` ports (4317/4318) stay — those are the real, wired-in ingest path.

### 🟡 Worth knowing, low-risk / latent

- `image.tag: "0.159.0"` is a manual override (not chart-tracked) with a comment referencing a stale chart version number ("Chart v0.155.0 ships appVersion 0.151.0") that doesn't match the actual pinned chart (`0.170.0`, appVersion `0.158.0`) — the comment wasn't updated across chart bumps. Not currently a functional problem: `0.159.0` is actually *ahead* of `0.170.0`'s own appVersion mapping and matches what the newer `0.172.0` chart (open PR #338 bumps to this) would ship by default — someone kept it in sync by hand. No `# renovate:` annotation tracks this field, same latent-drift risk pattern already flagged on `pihole`'s image tag, just not currently manifesting as actual drift.
- ClusterRole is broad (cluster-wide read on pods/nodes/deployments/daemonsets/replicasets/statefulsets/jobs/cronjobs/HPAs/services/events/namespaces, plus full CRUD on `coordination.k8s.io/leases`) — justified by the `clusterMetrics`/`kubeletMetrics`/`hostMetrics` presets, which genuinely need this breadth to scrape cluster-wide metrics. Not an over-grant given the component's actual job.
- `k8s_leader_elector/k8s_cluster` extension is active (daemonset mode auto-enables it so only one node's collector emits `k8s_cluster` metrics) — on this single-node cluster there's no real contention (only 1 pod exists), but it still performs periodic lease renewal against kine, adding to background lease-write load. Not currently causing crashes, just a minor structural contributor.

### 🟢 Well-configured, no action needed

- Chart version drift (0.170.0 → 0.172.0) already covered by open Renovate PR #338 (confirmed via `gh pr diff 338` — it only touches the `chart.spec.version` line, doesn't touch `image.tag`).
- Resource requests/limits set (`50m`/`128Mi` request, `256Mi` limit, CPU limit deliberately unset — consistent with the repo's Go-runtime convention). Chart's `useGOMEMLIMIT: true` default correctly derives `GOMEMLIMIT=204MiB` (80% of the 256Mi limit) — confirmed live in the rendered env vars, a nice automatic tie-in.
- `livenessProbe`/`readinessProbe` present via the chart's `health_check` extension (port 13133).
- Pipeline wiring is coherent and correctly cross-referenced: traces → OTLP receiver → Tempo (`tempo.telemetry.svc.cluster.local:4317`, matches the existing Tempo deployment); logs/metrics → `debug` exporter (explicitly documented as a placeholder "until we wire a metrics pipeline into Prometheus" — an honest, intentional gap, not an oversight).

### Kine/leader-election pattern (issue #355) check

Not present. Only 1 pod (daemonset, single node), 1 restart total over 6d4h, with `exitCode=0`/`reason=Completed` at `2026-08-28T18:02:31Z` — a clean/graceful restart (likely a Helm-release-triggered pod replacement), not a crash, and not the `context deadline exceeded` lease-timeout fingerprint. Does not land in or near the confirmed ~22:20 UTC cascade window on 2026-08-28.
