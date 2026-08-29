# cert-manager (cert-manager)

**Namespace:** cert-manager
**Chart version:** v1.21.1 (jetstack/cert-manager) — current upstream latest, zero drift
**Audit date:** 2026-08-28

Jetstack cert-manager (controller + cainjector + webhook), issuing Let's Encrypt certs via Cloudflare DNS-01 for every app in this repo that needs TLS.

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `v1.21.1` — the actual latest available upstream (verified via `helm search repo --versions`). Nothing for Renovate to even queue.
- RBAC is a much better pattern than alloy's: instead of one broad ClusterRole, upstream ships per-function scoped ClusterRoles (`cert-manager-controller-issuers`, `-certificates`, `-orders`, `-challenges`, `-certificatesigningrequests`, etc.) — genuine least-privilege, verified by rendering the chart.
- Pod + container securityContext on all three Deployments (controller, cainjector, webhook): `runAsNonRoot`, seccomp `RuntimeDefault`, all capabilities dropped, `readOnlyRootFilesystem: true`, no privilege escalation.
- Resource requests/limits set on all three components, matching declared HelmRelease values exactly on the live cluster.
- CRD lifecycle uses the modern, correct Flux pattern (`crds.enabled: true` in Helm values + `install.crds: CreateReplace` / `upgrade.crds: CreateReplace` in the HelmRelease) rather than a separate vendored CRD bundle.
- Cloudflare API token is genuinely SOPS-encrypted (checked the file directly — not a plaintext leak with a misleading `.sops.yaml` name), with a `.example` template for onboarding.
- Both `letsencrypt-prod` and `letsencrypt-staging` ClusterIssuers are `READY=True`, actively issuing (9+ certs across 6+ namespaces, oldest 115 days old, all `READY=True`).
- Services are `ClusterIP` only.

### 🔴 Real operational issue found (caught live, not a static config gap)

- **The controller and cainjector pods are crash-restarting repeatedly**: 13 restarts (controller) and 15 restarts (cainjector) over a 21-day pod lifetime. `--previous` logs show the root cause: leader-election lease renewal timing out against the API server (`Put ".../leases/cert-manager-cainjector-leader-election": context deadline exceeded`), which `controller-runtime` treats as fatal ("leader election lost") and exits the process, causing a restart. This is not a cert-manager misconfiguration — it's controller-runtime's by-design fail-safe behavior when it can't confirm leadership in time.
- Matches a previously-identified cluster constraint: single-node k3s with kine/SQLite as the datastore has a scalability ceiling on simultaneous coordination-lease updates. cert-manager's controller and cainjector both mandate leader-election with no supported way to disable it safely on a single replica, making them repeat victims whenever the API server has a slow patch. Not fixable from cert-manager's config — it's a cluster-architecture-level constraint affecting any controller-runtime-based operator that leader-elects, and it's a recurring pattern (spread across multiple days, not tied to one incident).
- Webhook pod has 1 restart in 21 days — much less affected, consistent with it not doing leader election.

### 🟡 Worth knowing, not clearly actionable

- `readinessProbe` is inconsistent across the three Deployments: webhook has both liveness+readiness, controller has liveness only, cainjector has neither. Verified via rendered templates — this is the chart's own default per-component design, not something introduced locally.
- No NetworkPolicy (same repo-wide pattern noted for alloy — not repeated in full per-component going forward).
