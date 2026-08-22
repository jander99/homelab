# csi-hostpath-sc → Longhorn migration completion

Date: 2026-08-22

All 11 csi-hostpath-sc PVCs across 8 apps migrated to Longhorn with no data loss:

- prowlarr (PR #313) — single PVC
- radarr (PR #314) — single PVC
- sonarr (PR #315) — single PVC
- qbittorrent (PR #317, contamination fix #326) — 2 PVCs (config + gluetun)
- sabnzbd (PR #319, #320, #321, recovery #324) — 2 PVCs (config + gluetun); config PVC required a post-incident recovery from a pre-incident kopia snapshot (see `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md`)
- tdarr (PR #328) — 2 PVCs (server-data + node-config)
- pihole (PR #329) — HelmRelease-managed
- authentik (PR #331) — HelmRelease + bitnami StatefulSet

Pattern: kopiur Restore CR + storageClassName change + snapshot policy snapclass update, per app, in 3 ordered commits.

## Incidents during this migration

- **qbittorrent/sabnzbd cross-contamination:** a multi-source `SnapshotPolicy` silently captured only the first source, causing `qbittorrent-gluetun-config` to restore from `qbittorrent-config`'s data and `sabnzbd-config` to restore nothing useful. Fixed by splitting policies to one source each (PR #318) before re-running those migrations.
- **sabnzbd-config data loss:** the failed restore above was recorded as a status note rather than a hard stop, the app was scaled back up on a fresh blank PVC, and it ran on blank config for ~90 minutes before being noticed. Recovered from a pre-incident kopia snapshot; this incident is why the plan's Constraint 9 ("a failed Restore CR is a hard stop, not a deferred TODO") exists.
- **authentik HelmRelease upgrade failure:** changing the bitnami/postgresql chart's `persistence.storageClass` value cannot be applied in place to an existing StatefulSet — `volumeClaimTemplates[].spec.storageClassName` is immutable, so Kubernetes rejected Helm's patch and helm-controller auto-rolled the Helm release record back. This was bookkeeping-only (the pod and the already-migrated PVC were never touched); fixed with `kubectl delete statefulset --cascade=orphan` (preserves pod + PVC) followed by a `flux suspend`/`flux resume` cycle to reset helm-controller's stalled retry counter. See memory `helm-statefulset-immutable-storageclass`.

## Plan document corrections found during execution

- Task 8 referenced `k3s/applications/authentik/helmrelease.yaml`; the real file is `k3s/infrastructure/configs/authentik/helmrelease.yaml` (`k3s/applications/authentik/` is not wired into any Flux kustomization — it only holds historical migration artifacts).
- The one-off `Snapshot` CR examples (Task 9 Step 3a and Step 4) used `spec.policyName`; the actual CRD field is `spec.policyRef.name`.

## Out of scope (deferred)

- 4 local-path PVCs (prometheus, loki, tempo, sabnzbd-downloads) — need separate migration to csi-hostpath-sc first.

See `docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md` for the full design.
