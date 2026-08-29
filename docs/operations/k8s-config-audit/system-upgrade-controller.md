# system-upgrade-controller (system-upgrade)

**Namespace:** system-upgrade
**Image:** rancher/system-upgrade-controller:v0.20.1 — current, bumped this week via PR #353
**Audit date:** 2026-08-29

Rancher's k3s auto-upgrade controller. Unlike every other component in this series, this one was already the subject of intensive same-week investigation (PRs #349–#353, GitHub issue #354) rather than being audited cold — this pass is a confirmatory check against the live cluster plus the one new finding below, not a first look.

## Findings

### 🟢 Well-configured, no action needed

- Controller image v0.20.1 confirmed live and matches the pinned manifest — genuinely fixes the v0.14.0 `window` field gap documented at length in `plan.yaml`'s own history comment.
- `Plan/server-plan` status: `Complete` at `2026-08-28T17:22:49Z`, `latestVersion: v1.36.4-k3s1` matching the live node's `kubeletVersion` exactly — auto-upgrade genuinely worked end-to-end.
- `SYSTEM_UPGRADE_JOB_KUBECTL_IMAGE: rancher/kubectl:v1.36.2` (the PR #353 fix) is live in the ConfigMap — correctly matches the cluster's `+/-1` kubectl-server skew policy against server v1.36.4.
- Resource requests/limits present (`10m/32Mi` request, `128Mi` limit) — a local addition on top of upstream's vendored manifest (documented as such in-file), reasonable for observed idle usage.
- securityContext hardened: `runAsNonRoot`, UID/GID 65534, all capabilities dropped, seccomp `RuntimeDefault` — consistent with every other component in this audit.
- RBAC is scoped (not cluster-admin): node get/update/patch, pod eviction/delete, Job management, Plan read/write — the minimum needed to cordon/drain/swap the k3s binary on its own node. `SYSTEM_UPGRADE_JOB_PRIVILEGED: "true"` on the upgrade Job itself is required and justified (it swaps the host k3s binary) — same precedent already noted for `csi-driver-smb`'s node plugin.
- `window: Sundays 04:00-05:00 UTC` is present and, per `kubectl explain`, valid against the live CRD — correctly restored after the v0.14.0/v0.16.0 version-skew misdiagnosis documented in-file. Next real test is the upcoming window (2026-08-31), already tracked by issue #354's verification checklist — nothing further to add here.

### 🔴 Confirmed instance of the kine/leader-election pattern (issue #355) — new occurrence, not from the known cascade window

Live pod `system-upgrade-controller-bb795c5fb-m49pf` shows 2 restarts over 4h38m. `--previous` logs show the familiar signature — but at a **different timestamp** than every other confirmed instance:

```
2026-08-29T03:21:02Z  "Failed to renew lease" lock="system-upgrade/system-upgrade-controller" err="context deadline exceeded"
2026-08-29T03:21:02Z  level=fatal msg="leaderelection lost for system-upgrade-controller"
```

Every other confirmed instance on issue #355 traces back to the single correlated 22:19:59–22:20:37Z cascade on 2026-08-28. This one is ~3 hours later and, notably, from *today* (2026-08-29), not the same historical window — direct evidence the underlying kine lease-contention ceiling is still being hit in ordinary day-to-day operation, not just during the one heavy-load event this audit session itself may have contributed to. Worth adding to issue #355 as the pattern's continuation, not closure.

### 🟡 Worth knowing, not actionable

- A stale `kube-system` events entry (~11h old at check time) shows an upgrade Job pulling `rancher/kubectl:v1.30.3` — this is leftover event history from the pre-PR#353 upgrade that completed at 17:22:49Z, before the kubectl-image fix merged (23:51:49Z). No new Job has run since (Plan `Complete` condition unchanged since 17:22:49Z), so this isn't a live gap — just aging event-log noise that will roll off naturally. Confirmed the *next* Job (Sunday's window) will use the ConfigMap's `v1.36.2` value, per the live ConfigMap check above.
