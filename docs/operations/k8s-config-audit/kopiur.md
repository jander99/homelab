# kopiur (kopiur-system + cross-namespace)

**Chart version:** 0.10.3 (drift to 0.10.5 already covered by open Renovate PR #338)
**Audit date:** 2026-08-28

Cluster-wide backup/snapshot system (Kopia-based). This is the most operationally significant component in the audit series — real prior incident history exists here (see "Already-known issues" below).

## Findings

### 🔴 Confirmed instance of the kine/leader-election pattern (issue #355) — near-exact same timestamp as the flux2 cascade

`kopiur-controller` has 34 restarts over 6d4h. `--previous` logs show it lost its leader lease at **2026-08-28T22:20:00.408Z** (`could not renew the leader lease within the renew window ... exiting to re-elect`) — essentially the same moment the flux2 audit found all 6 Flux controllers crash together (22:20:20Z–22:20:37Z). This is strong independent corroboration that a real multi-controller cascade happened cluster-wide at ~22:20 UTC on 2026-08-28, not isolated per-component noise — see issue #355 for the consolidated picture across all three confirmed instances. kopiur's leader-election implementation is more graceful than a naive client-go consumer (logs show it tries "re-confirming our hold within the remaining margin" before giving up), but still hits the same wall.

`kopiur-webhook`: 0 restarts — doesn't leader-elect, consistent with every other non-leader-electing component staying stable throughout this whole audit series.

### 🟡 Worth knowing, structurally hard to fix / minor

- Neither `kopiur-controller` nor `kopiur-webhook` has a `resources.limits` block at all — only `requests` (100m/128Mi and 25m/64Mi respectively). This deviates from the repo's otherwise-consistent convention (memory-only limit + cpu request, seen in every other component this session). Not dangerous on its own, but worth aligning for consistency.
- Chart version 0.10.3 → 0.10.5 drift is already covered by the open Renovate PR #338 (same PR bundling alloy/loki/tempo/opentelemetry-collector) — not a gap.

### 🟢 Well-configured, no action needed

- securityContext hardened identically to every other component in this audit: `runAsNonRoot`, UID/GID 65534, all capabilities dropped, `readOnlyRootFilesystem: true`, seccomp `RuntimeDefault`.
- `job-cleanup` CronJob's RBAC is properly minimal: namespaced Role, `get/list/delete` on `jobs` only, nothing else.
- Every namespace with a `kopiur-repo` PV/PVC pair (11: authentik, gatus, headlamp, kopiur-system, media, monitoring, pihole, portainer, qbittorrent, sabnzbd, tdarr) exactly matches every namespace referenced by a SnapshotPolicy — no missing pairs, no orphaned ones.
- All ~20 recent scheduled Snapshots across every namespace show `Succeeded` — the backup system is healthy in current operation.
- All 17 `csi-hostpath→longhorn` migration Restore CRs across every namespace show `Completed` — the entire migration effort documented in memory is fully finished, nothing left half-migrated.

## Already-known issues, status check

- **Multi-source SnapshotPolicy bug** ([[kopiur-multi-source-snapshot-policy-silently-drops-sources]]): **Fixed and holding.** Checked all 16 current SnapshotPolicy files — every one declares exactly 1 source. No regression.
- **sabnzbd data-loss incident** ([[sabnzbd-config-data-loss-2026-08-21]]): **Fully resolved.** PR #324 merged 2026-08-21T23:27:43Z. Live `sabnzbd-config` PVC is on `longhorn`. A `sabnzbd-config-longhorn-migration` Restore CR (source: `SnapshotRef`, matching the manual targeted-restore recovery path documented in the incident) shows `Completed`.
- **kopiur-repo-per-namespace rule**: Still correctly followed everywhere (see 🟢 above).
- **Privileged mover mode** (pihole, etc.): Not independently re-verified in this pass beyond confirming pihole's snapshots are `Succeeded` (which they wouldn't be if the PermissionDenied bug had regressed) — deeper Job-spec verification out of scope for this pass.
