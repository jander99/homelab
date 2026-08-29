# loki (telemetry)

**Namespace:** telemetry
**Chart version:** 18.11.0 (drift to 18.11.7 already covered by open Renovate PR #338)
**Audit date:** 2026-08-28

Loki (monolithic deployment mode), receiving logs shipped by alloy (already audited — `telemetry` namespace).

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `18.11.0`; drift to `18.11.7` is a patch bump already covered by open Renovate PR #338 (bundled with alloy/tempo/opentelemetry-collector) — not a gap. Checked the actual changelog entries for 18.11.1→18.11.7: minor bugfixes only (a PDB-rendering fix for disabled components, a sidecar image bump, a StatefulSet label fix), nothing safety-critical being missed by staying on 18.11.0 for a few more days.
- `deploymentMode: Monolithic` with all other component replicas zeroed renders exactly as intended — checked the actual rendered output: only 6 legitimate Services (gateway, gateway-exporter, canary, loki, loki-headless, loki-memberlist) and zero stray PodDisruptionBudgets. The "Fix Service/PDB rendered for disabled components" bug mentioned in later chart changelogs (fixed in 18.11.2) does not appear to affect this specific values configuration even at 18.11.0 — verified empirically, not just assumed safe.
- StatefulSet pod: `runAsNonRoot`, UID/GID 10001, seccomp `RuntimeDefault` at pod level; container adds `readOnlyRootFilesystem: true`, all capabilities dropped, no privilege escalation. Liveness + readiness probes both present and correctly configured.
- RBAC is tight: single ClusterRole, `get/watch/list` on `configmaps`/`secrets` only — needed for the chart's bundled `kiwigrid/k8s-sidecar` (dashboard/rule auto-loading from labeled ConfigMaps), not an over-grant. `automountServiceAccountToken: true` is therefore justified here, unlike the unnecessary mount found on tdarr.
- Live PVC (`storage-loki-0`, 20Gi, `local-path`) matches declared config exactly.
- Multi-tenancy wiring is consistent end-to-end: `auth_enabled: true` on Loki's side, and alloy's already-audited `loki.write` config sets `tenant_id = "homelab"` (translates to the required `X-Scope-OrgID` header) — the two configs agree with each other.
- All 3 pods (`loki-0`, `loki-canary`, `loki-gateway`) show **0 restarts** — loki-0 over 6d4h, gateway over 6d2h, canary over 20d. Extremely stable.
- Extensive, accurate in-repo documentation of two real prior incidents (gateway anti-affinity deadlock on single-node rolling updates, and the `null` vs `{}` Helm map-merge footgun that caused it) — verified the `null` claim directly: rendering with `affinity: null` produces no affinity block, confirming the fix is real and still in effect.

### 🟡 Worth knowing, not clearly actionable

- Loki's storage PVC (`local-path`, `telemetry` namespace) has no kopiur backup coverage — `telemetry` is not among the 11 namespaces with a `kopiur-repo` PV/PVC pair (confirmed against the kopiur audit's namespace list). Given this is log data rather than app state, likely an intentional/acceptable tradeoff (matches the existing `local-path-pvcs-need-csi-hostpath-for-snapshots` constraint — snapshotting would require a storage-class migration first), but worth the owner explicitly confirming that's still the intended posture rather than an oversight.
- CPU limits intentionally unset (documented rationale: avoid Go GC throttling) — consistent with the same choice made on alloy/flux2/cert-manager elsewhere in this audit.

### Kine/leader-election pattern (issue #355) check

Not applicable and not present. Zero restarts across all 3 pods rules this out entirely — no leader-election flags in the rendered StatefulSet/Deployment args either (single-replica monolithic mode has no need for it). No evidence of any disruption during the 2026-08-28 ~22:20 UTC window that affected flux-system and kopiur-system.

### 🔴 Clear actionable gaps

None found.
