# flux2 (flux-system)

**Namespace:** flux-system
**Chart version:** 2.19.0 (appVersion 2.9.1) — current upstream latest, zero drift
**Audit date:** 2026-08-28

Flux's own GitOps controllers (source, kustomize, helm, notification, image-reflector, image-automation), managing every other component audited in this series. Split across two locations: `k3s/infrastructure/controllers/flux2/` (Helm-managed, post-migration) and `k3s/clusters/homelab/flux-system/` (the original `flux bootstrap`-vendored manifest bundle).

## Findings

### 🟢 Well-configured, no action needed

- Chart already at latest upstream version (`2.19.0`, appVersion `2.9.1`) — zero drift, no open Renovate PR needed.
- Resource requests/limits (per-controller, derived from krr P95 data, CPU limits deliberately omitted with a documented rationale) match exactly between declared HelmRelease values and live Deployments across all 6 controllers.
- SecurityContext hardened identically to every other component audited so far: `runAsNonRoot`, UID 65534, all capabilities dropped, `readOnlyRootFilesystem: true`, seccomp `RuntimeDefault`, plus pod-level `fsGroup: 1337`.
- The `crd-controller` ClusterRoleBinding's wildcard-ish RBAC (`["*"]` on one rule) is not a misconfiguration — Flux's entire purpose is applying arbitrary manifests from git, so near-cluster-admin scope is inherent to the tool, not a local choice.
- The bootstrap→Helm migration (PRs #285, #286, #287, #288, #289) is genuinely complete and clean on the live cluster: the `postRenderer` JSON-patch correctly strips the phantom `source-watcher-controller` RBAC subject (verified live — `crd-controller` ClusterRoleBinding has exactly 6 subjects, none named that), the orphaned `artifactgenerators.source.extensions.fluxcd.io` CRD has already been purged (confirmed absent), and all 6 controllers are genuinely Helm-managed (`app.kubernetes.io/managed-by: Helm`) at the correct post-migration versions.

### 🟡 Worth knowing, not clearly actionable

- `helmrelease.yaml`'s comments are stale — they narrate "Phase 1 of the bootstrap → Helm chart migration" and reference `k3s/clusters/homelab/flux-system-components/patches/resource-patch.yaml`, but that directory was deleted in the Phase 3 PR (#287) and the migration is fully complete. Purely a documentation-drift issue, zero functional impact — worth a quick comment cleanup next time this file is touched, not urgent enough for its own PR.
- Small cosmetic artifact: the live `source-controller` Deployment still carries a leftover label `kustomize.toolkit.fluxcd.io/name: flux-system-components` from before the Helm takeover — doesn't affect selectors or ownership.

### 🔴 Confirmed instance of the kine/leader-election pattern (issue #355) — most severe instance so far

All 6 Flux controllers show substantial restart counts (helm-controller 21, kustomize-controller 23, source-controller 22, notification-controller 23, image-reflector-controller 23, image-automation-controller 25). `--previous` logs show all six controllers lost their leader-election lease and crashed within the same 17-second window on 2026-08-28 (22:20:20Z–22:20:37Z) — a correlated, cluster-wide event across the whole `flux-system` namespace at once, not independent per-pod noise like the cert-manager/csi-driver-smb instances. This is much closer to the severe "cascade" failure mode from the original 2026-08-21 incident (`k3s-kine-scalability-ceiling` memory) than to the mild, spread-out restarts seen elsewhere.

**Correction to the original hypothesis:** the research agent that found this speculated it might correlate with a burst of `flux reconcile` commands run later in this same session verifying PR #353's merge. Checked directly against GitHub's authoritative merge timestamps: PR #353 merged at **23:51:49Z**, over 90 minutes *after* the 22:20 crash window — ruled out. PR #351, however, merged at **22:07:27Z**, only 13 minutes before the crash, and that merge was followed by a `flux reconcile` burst (multiple `--with-source=false` force-reconciles across `infra-controllers`/`infra-configs`/`kopiur-policies`) plus `kubectl apply --dry-run=server` validation runs during this same session's PR #352 work — both plausible contributors to API write load in that window. This is a timing correlation, not a proven causal link. Kubernetes' default event TTL (~1h) had already rolled off this window by the time it was investigated, so broader cluster-wide impact (e.g. whether any node briefly went `NodeNotReady`, as in the 2026-08-21 incident) could not be independently confirmed or ruled out from this session — only the six controllers' own pod logs were available as evidence.
