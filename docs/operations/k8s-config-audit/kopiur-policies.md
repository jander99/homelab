# kopiur-policies (cross-namespace SnapshotPolicy/SnapshotSchedule CRs)

**Audit date:** 2026-08-29

16 `SnapshotPolicy` + 16 `SnapshotSchedule` pairs, one per app PVC, backing every scheduled backup in the cluster. Config-only — no controller of its own (reconciled by `kopiur-controller`, already audited separately in `kopiur.md`), so not a candidate for the leader-election pattern tracked on issue #355.

## Findings

### 🟢 Well-configured, no action needed

- **Multi-source regression check ([[kopiur-multi-source-snapshot-policy-silently-drops-sources]]): still holding.** All 16 `SnapshotPolicy` files declare exactly 1 `sources:` entry — re-verified independently of the `kopiur.md` pass with a direct count.
- All 16 policies show a recent `LAST-SNAPSHOT` (9 minutes to 55 minutes old at check time) and `LAST-VERIFIED` within the last 21 hours — every scheduled backup in the cluster is actively succeeding, not just configured.
- `tdarr-server-data`'s last 30 hourly scheduled snapshots (spot-checked via `kubectl get snapshots`) are 100% `Succeeded` — no silent failures hiding behind a healthy-looking `SnapshotPolicy` status.
- `volumeSnapshotClassName: longhorn-snapclass` is consistent across all 16 policies (one, `radarr`, carries an explicit in-file comment documenting its `csi-hostpath-snapclass` → `longhorn-snapclass` migration) — matches the completed csi-hostpath→longhorn migration confirmed in `kopiur.md` and now further confirmed by `csi-hostpath.md`'s orphaned-StorageClass finding: nothing here still points at the old class.
- `credentialProjection.enabled: true` present on every policy — consistent with the `[[csi-hostpath-to-longhorn-restore-cr]]` memory note's requirement.
- Per-app `mover.securityContext`/`podSecurityContext` UID/GID values are correctly differentiated by actual container UID (e.g. radarr/prowlarr both `1027:100` as LinuxServer-base siblings) rather than copy-pasted — spot-checked against the app's own Deployment `securityContext` where audited elsewhere in this series (radarr.md).

### 🟡 Worth knowing — corroborates an open hypothesis on issue #355

Every one of the 16 `SnapshotSchedule` resources uses the identical cron `"H * * * *"` (hourly, hash-distributed minute per resource name — not a literal fixed minute). This directly corroborates the fifth data point already posted on issue #355 (the `snapshot-controller` audit's hypothesis that hourly `SnapshotSchedule` resources could cluster several apps' snapshot/CSI activity into the same few-minute window and contribute to kine lease pressure). Confirms the mechanism exists as described; doesn't independently prove clustering actually happens at any specific minute — hash distribution across 16 names would need to be checked against actual per-schedule trigger minutes to confirm real overlap. Not filing as a new data point on #355 since it doesn't add a new confirmed crash, just supporting evidence for the existing hypothesis there.

### 🟢 No action needed

- `mover.cache` on every policy uses `local-path` StorageClass with `mode: Ephemeral` — consistent, low-risk (cache only, not the backup destination).
