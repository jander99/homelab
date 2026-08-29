# snapshot-controller (kube-system)

**Chart version:** 5.2.0 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Generic Kubernetes VolumeSnapshot controller — the cluster-wide counterpart to per-CSI-driver snapshotter sidecars (already audited in csi-driver-smb and longhorn).

## Findings

### 🔴 Confirmed instance of the kine/leader-election pattern (issue #355) — 5th independent controller, 4th namespace, same cascade window, and a strong new causal lead

77 restarts over 14 days (~5.5/day average — chronic, not one-off). `--previous` logs show the exact standard signature: `"Error retrieving lease lock" err="client rate limiter Wait returned an error: context deadline exceeded"` → `"Failed to renew lease"` → `"Stopped leading"`, crashing at **2026-08-28T22:20:03.166Z** — squarely inside the confirmed cascade window (22:19:59.891Z–22:20:37Z) already established across flux-system, kopiur-system, and longhorn-system. This is a 5th independent controller crashing within the same ~38-second window, now spanning 4 namespaces.

**New and more concrete causal lead than anything found so far in this audit series:** the log lines immediately preceding this crash (22:16:01–22:19:01) show snapshot-controller actively processing *scheduled* VolumeSnapshot creation across four different namespaces in quick succession — `authentik` (22:16:00), `sabnzbd` (22:16:00), `media/sonarr` (22:18:00), `monitoring/grafana` (22:19:00) — each involving PVC finalizer adds/removes and CSI driver round-trips. This lines up far better with the existing `k3s-kine-scalability-ceiling` memory's own root-cause note ("kopiur's Restore CR and kopiur-system controllers contribute lease churn... many short-lived snapshot-clone cycles → many lease updates → kine queue pressure") than an earlier, weaker hypothesis about session tooling activity (`flux reconcile`/`kubectl apply --dry-run` commands run ~90+ minutes prior during this same audit session) — that hypothesis has been retracted in issue #355 in favor of this one. Not fully closed: most kopiur `SnapshotPolicy` resources run on a daily `cron: "H 3 * * *"` schedule, which doesn't obviously explain a 22:16-22:20 UTC occurrence, but separate hourly `SnapshotSchedule` resources (`cron: "H * * * *"`, hash-distributed minute) could plausibly cluster several apps' snapshot activity into the same few-minute window every hour — worth a dedicated trace if this gets prioritized.

### 🟢 Well-configured, no action needed

- Chart pinned at `5.2.0` — confirmed current upstream latest, zero drift, no Renovate PR needed.
- `replicaCount: 1` is **already correctly set** with a documented rationale in the HelmRelease comment — unlike longhorn's CSI sidecars (issue #356), this component does not have an unnecessary-replica-count problem to fix.
- RBAC is properly scoped: PV/PVC (get/list/watch, PVC update for finalizers), the snapshot/volumegroupsnapshot CRDs, events, and namespaced `coordination.k8s.io/leases` for its own leader-election — no secrets, no configmaps, no cross-namespace over-grant.
- Container securityContext is well hardened: `runAsNonRoot`, `runAsUser: 1000`, all capabilities dropped, `readOnlyRootFilesystem: true`.
- Liveness and readiness probes both present, hitting `/healthz/leader-election` on port 8080.
- Resources match declared config exactly on the live Deployment (`10m`/`100Mi` request, `100Mi` limit — krr-derived, documented rationale, matches this repo's standard convention).
- Webhook deliberately disabled (`webhook.enabled: false`) with a documented, sound rationale (avoids a cert-manager dependency for VolumeGroupSnapshot validation not in use on this single-node homelab).

### 🟡 Worth knowing, minor

- Deployment/pod names carry a `kube-system-` prefix (`kube-system-snapshot-controller`) from Helm release-name prefixing — same naming pattern that caused the real dcgm-exporter `postRenderers` bug found earlier in this audit series. This component doesn't use `postRenderers` at all, so that specific failure mode doesn't apply here — just flagging the naming pattern as something to watch for if a patch mechanism is ever added later.
- Pod-level securityContext renders as `{}` — no seccompProfile set at pod level; minor, not independently confirmed whether the chart exposes a knob for this.
