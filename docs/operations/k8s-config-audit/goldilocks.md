# goldilocks (goldilocks)

**Namespace:** goldilocks
**Chart version:** 11.0.0 (fairwinds-stable/goldilocks) — current upstream latest, zero drift
**Audit date:** 2026-08-28

Fairwinds Goldilocks: VPA-recommendation dashboard, recommend-only (no admission controller, no auto-updater).

## Findings

### 🟡 Actionable but minor — chart default, fixable via values override

- No `resources.limits` on any of the 3 pods (`goldilocks-controller`, `goldilocks-dashboard`, `vpa-recommender`) — only `requests` are set (25m/256Mi, 25m/256Mi, 50m/500Mi respectively). Confirmed this is the chart's own default (`controller.resources`, `dashboard.resources` in `values.yaml` both ship `limits: {}`), not something stripped by our override — our `helmrelease.yaml` sets zero `resources` values at all, so it's 100% chart defaults. Unlike alloy/portainer's *unfixable* upstream gaps, this one **does** have a working values knob (`controller.resources.limits.memory`, `dashboard.resources.limits.memory`, `vpa.recommender.resources.limits.memory` per `helm show values fairwinds-stable/goldilocks --version 11.0.0`) — matching this repo's established memory-limit convention (seen in alloy, cert-manager, flux2, etc.) would just require adding 3 small blocks to `values:`.

### 🟢 Well-configured, no action needed

- Chart pinned at `11.0.0` — confirmed current upstream latest (`helm search repo --versions`), zero drift, no Renovate PR needed.
- **VPA dependency genuinely present and working, not just assumed** — confirmed the `verticalpodautoscalers.autoscaling.k8s.io` CRD is installed (matches this HelmRelease's own `crds: CreateReplace` bundling it), and live `kubectl get vpa -A` shows real recommendations (`PROVIDED: True`) across 18 opted-in namespaces (label `goldilocks.fairwinds.com/enabled=true`) — this is an actively functioning feedback loop, not dead config.
- **Recommend-only design genuinely enforced**: `vpa.admissionController.enabled: false` and the chart's own `updater.enabled: false` default mean no mutating webhook and no auto-updater pod exist on the cluster (confirmed — only 3 pods total: controller, dashboard, recommender). The HelmRelease's own comment explains this precisely and correctly (avoids the webhook single-point-of-failure + "Auto" mode this deployment deliberately avoids).
- All 3 containers hardened well: `runAsNonRoot`, non-root UID, `readOnlyRootFilesystem: true`, all capabilities dropped, seccomp `RuntimeDefault`.
- Liveness/readiness probes present on all 3 containers.
- Ingress uses cert-manager TLS + reuses the existing authentik-forwardauth Traefik middleware for auth (goldilocks has no built-in auth of its own) — correct given the dashboard would otherwise be unauthenticated.
- 0 restarts across all 3 pods over 4d7h — completely stable.
- Broad-looking ClusterRole set (9 ClusterRoles from the bundled `vpa` sub-chart) is inherent to VPA's design — it needs cluster-wide read access to pods/deployments/resource-usage metrics to compute recommendations for any opted-in namespace, not a local over-grant.
- The `1h` HelmRepository interval is deliberately tuned with a documented incident history (PRs #250, #251 — 24h interval previously caused reconcile stalls on republished `index.yaml`).

### Kine/leader-election pattern (issue #355) check

Not applicable. None of the 3 pods show any leader-election flags in their rendered args, and 0 restarts over 4d7h rules out any instability of any kind.

### 🔴 Clear actionable gaps

None found.
