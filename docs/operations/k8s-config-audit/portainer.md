# portainer (portainer)

**Namespace:** portainer
**Chart version:** 239.6.0 (latest available: 245.0.0 — not yet queued, see note below)
**Audit date:** 2026-08-28

Full-featured Kubernetes cluster management UI.

## Findings

### 🟡 Worth knowing, structurally hard to fix (upstream limitation) — largest blast-radius pairing found so far

- **No `securityContext` at all** — pod and container level both render as `{}` on the live Deployment. Confirmed this is an upstream chart limitation, not something stripped by our values override: `helm show values portainer/portainer --version 239.6.0` has zero `securityContext` key anywhere in the chart's own defaults — no values.yaml knob to set one even if we wanted to.
- **This pairs with the chart's own `cluster-admin` binding** — the rendered `ClusterRoleBinding` binds the built-in `cluster-admin` ClusterRole directly to `portainer-sa-clusteradmin` (the SA name makes the intent explicit). This is inherent to what Portainer is — a full cluster-management UI needs to create/delete namespaces, manage RBAC, deploy arbitrary workloads — so `cluster-admin` is essentially required for full functionality, not a misconfiguration. But combined with the missing securityContext above, this is the largest blast-radius pairing of any component audited in this series: a cluster-admin-privileged pod running with zero pod-level hardening (no `runAsNonRoot`, no dropped capabilities, no `readOnlyRootFilesystem`). Not fixable from our config layer without forking the chart.
- Migration artifacts in `migration/` (from the local-path→csi-hostpath-sc→longhorn PVC migration history, PRs #298/#310) are well-documented as intentionally NOT Flux-managed, explaining exactly why in the kustomization.yaml comment. Not dead config nobody understands — it's a deliberate historical record. No action needed.
- `postRenderers` patch (probe-timing fix, PR #256) already spot-checked directly and confirmed working correctly — the Deployment name matches the patch target exactly (unlike dcgm-exporter's chart, this one doesn't prefix the resource name).

### 🟢 Well-configured, no action needed

- Image pinned explicitly (`portainer/portainer-ce:2.39.6`, matches chart appVersion) — not `:latest`.
- Resource requests/limits set and match declared HelmRelease values exactly on the live Deployment.
- Ingress uses TLS via cert-manager (`letsencrypt-prod`), `traefik` entrypoint `websecure` only — no plaintext HTTP path exposed.
- Service is `ClusterIP` — only reachable via the Ingress, not directly exposed.
- Live pod: 0 restarts over 6 days — completely stable.
- **Chart version drift (239.6.0 → 245.0.0) is not actually a gap** — checked directly: this repo's Renovate runs on a weekly schedule (`"schedule": ["before 6am on Monday"]` in `renovate.json`), not continuously. All 3 currently-open Renovate PRs (#337, #338, #339) were created at exactly `2026-08-24T05:14 UTC` — last Monday's run. Portainer's bump simply hasn't hit its next scheduled window yet (2026-08-31); no config exclusion, no neglect.

### Kine/leader-election pattern (issue #355) check

Not applicable. Portainer is a UI/API server with `replicaCount: 1` and no leader-election flags in its rendered Deployment args — architecturally not exposed to this pattern. 0 restarts confirms no instability of any kind, consistent with that.

### 🔴 Clear actionable gaps

None found.
