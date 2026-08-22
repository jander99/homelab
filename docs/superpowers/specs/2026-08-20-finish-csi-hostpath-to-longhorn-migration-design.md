---
title: Finish csi-hostpath-sc → Longhorn PVC migration (8 apps, 11 PVCs)
date: 2026-08-20
status: approved
---

# Finish csi-hostpath-sc → Longhorn PVC migration

## Context

The csi-hostpath-sc StorageClass is failing in this cluster: backups have been failing silently for up to 2d17h, the CSI hostpath provisioner times out on snapshot restores, and the local-path → csi-hostpath-sc migration (PR #298) is now in a state where every PVC still on csi-hostpath-sc is at risk.

The Longhorn CSI driver is installed (PR #306). Five apps have already been successfully migrated to `longhorn`: gatus (#307), headlamp (#309), portainer (#310, fix #312), monitoring/alertmanager + monitoring/grafana (#311). This spec finishes the remaining 11 PVCs across 8 apps.

Goal: move every csi-hostpath-sc PVC to Longhorn with no data loss, applying the established pattern.

## Scope

**In scope (11 PVCs across 8 apps):**

| App | Namespace | PVC(s) | Pattern | Privileged mover |
|-----|-----------|--------|---------|------------------|
| prowlarr | media | prowlarr-config (2Gi) | Raw PVC | No |
| radarr | media | radarr-config (2Gi) | Raw PVC | No |
| sonarr | media | sonarr-config (2Gi) | Raw PVC | No |
| qbittorrent | qbittorrent | qbittorrent-config (5Gi), gluetun-config (1Gi) | Raw PVC | No |
| sabnzbd | sabnzbd | sabnzbd-config (5Gi), gluetun-config (1Gi) | Raw PVC | No |
| tdarr | tdarr | tdarr-server-data (10Gi), tdarr-node-config (1Gi) | Raw PVC | Yes |
| pihole | pihole | pihole (1Gi) | HelmRelease | Yes |
| authentik | authentik | data-authentik-postgresql-0 (2Gi) | HelmRelease + StatefulSet | Yes |

**Out of scope (deferred to separate future work):**

- 4 local-path PVCs that need local-path → csi-hostpath-sc first:
  - monitoring/prometheus-kube-prometheus-stack-prometheus-db (20Gi, StatefulSet)
  - sabnzbd/sabnzbd-downloads (200Gi)
  - telemetry/storage-loki-0 (20Gi, StatefulSet)
  - telemetry/storage-tempo-0 (5Gi, StatefulSet)

- Kopiur system-level fixes (CSI hostpath provisioner timeout on sabnzbd restore)
- smb-media PVCs (already on a different StorageClass, not snapshot-eligible by design)

## Constraints / non-negotiables

1. **No data loss.** Every migration preserves the existing data via kopiur snapshot.
2. **Backup health verified before each Restore CR.** Per past session (S108), backup snapshots have been failing silently. Verify a recent successful snapshot exists before applying each Restore CR; pause and fix the backup system first if not.
3. **Match established pattern.** Restore CR + storageClassName change + snapshot policy snapclass change. Don't invent a new mechanism.
4. **Migration files NOT in kustomization resources.** Per portainer #312 lesson, imperative PVC manifests in `migration/` must not be Flux-managed if they conflict with the HelmRelease-managed PVC. **This applies to `kustomization.yaml` resources listings as well** — a stale `migration/pvc.yaml` listed there will be re-applied with the old storageClassName on every reconcile, fighting the new longhorn PVC in Flux dry-run.
5. **A failed or unretried Restore CR is a hard stop, not a deferred TODO.** Scale the app to 0 and leave it down rather than let it come back up on a substitute/auto-provisioned empty PVC. Do not proceed to the next app's migration task until the restore is fixed and re-run, or a human explicitly decides to abandon it. Real incident (2026-08-21): sabnzbd-config's restore failed, the failure was documented as "BLOCKED" in a task report, work moved on to other apps/tasks, and sabnzbd ran on a silently-reprovisioned blank config PVC for ~90 minutes before it was noticed — see `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md`.
6. **`Completed` phase is not proof of correct data — verify content.** Compare restored size against the source snapshot's `status.stats.sizeBytes` and spot-check that files have plausible pre-migration mtimes, not today's date. For multi-PVC apps especially, the restored PVC could be the right size with plausible mtimes and still contain the *wrong* PVC's data (qbittorrent-gluetun-config incident: got qbittorrent-config's data, gluetun regenerated its tunnel state so the corruption was invisible at the VPN layer). Use a per-app content verification table mapping each restored PVC to the files/directories it must and must not contain.
7. **Single-source snapshot policy is a precondition.** A kopiur `SnapshotPolicy` with multiple `sources:` only captures the **first** source — the rest are silently dropped, no error, no warning. The Restore CR that follows writes the wrong PVC's data into the target. Every policy backing a Restore CR must have exactly one `sources:` entry AND the most recent Snapshot CR's `status.resolved.sources` must list exactly one source matching the source PVC name. If either fails, the migration is BLOCKED until the policy is split per app/PVC.
8. **Source PVC deletion requires a verified, recently-completed snapshot for that exact source PVC.** Order is: scale down → verify latest snapshot has `status.phase: Succeeded` AND `status.resolved.sources` matches the source PVC name → delete source PVC → apply Restore CR. Never delete the source PVC based on a stale or empty snapshot check.
9. **Never delete user-facing cluster resources to recover from a Flux dry-run failure.** No `kubectl delete helmrelease`, `kubectl delete pvc <restored>`, or `kubectl delete deployment` to "fix" a stuck reconcile. Helm-controller GC will garbage-collect the chart-managed PVC and permanently destroy the restored data (portainer #310 incident). Safe tools, in order: `flux reconcile kustomization apps --with-source`, restart `helm-controller` pod, restart `kustomize-controller` pod, wait. **If a dry-run shows an unexpected value, FIRST `grep -rn <value> k3s/applications/<app>/`** — a stale `migration/` resource listing the old storageClassName is the most common cause (portainer #312). Controller restarts never fix a conflict that comes from the repo.
10. **Reverse-recovery procedure:** if you discover an app is running on a fresh/empty PVC after a migration completed (or after a failed/abandoned restore), recovery is a new Restore CR pinned via `spec.source.snapshotRef` to the last known-good **Discovered** Snapshot CR for that source path — NOT `fromPolicy`, because the policy's own post-incident scheduled snapshots are of the blank state and will silently restore nothing useful. Worked example: `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md`.

## Architecture

8 PRs total, one per app. Each PR has 3 ordered commits applied in sequence:

```
Per-app flow (3 commits in 1 PR):

  ┌─ Commit 1: migration/restore.yaml (operator-applied)
  │   - Restore CR pulls latest kopiur snapshot
  │   - Creates new PVC on longhorn
  │   - Pre-conditions: HelmRelease suspended, deployment scaled to 0,
  │     stale VolumeSnapshots cleared, old PVC deleted
  │   - Apply with: kubectl apply -f migration/restore.yaml
  │   - Verify: kubectl get restore -n <ns> → phase: Completed
  │
  ├─ Commit 2: storageClassName → longhorn
  │   - HelmRelease apps: edit k3s/applications/<app>/helmrelease.yaml
  │   - Raw PVC apps: edit k3s/applications/<app>/pvc.yaml
  │   - Flux reconciles → chart's PVC template matches existing PVC
  │   - Deploy / scale back to 1 replica
  │
  └─ Commit 3: volumeSnapshotClassName → longhorn-snapclass
      - Edit k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-<app>.yaml
      - Next scheduled snapshot uses longhorn-snapclass

  Optional follow-up cleanup PR per app:
    - If kustomization.yaml lists migration/* files, remove them
    - Portainer #312 lesson: imperative PVC manifests conflict with Flux's
      HelmRelease-managed PVC
```

## Per-app specifics

### A. HelmRelease-managed apps

**pihole, authentik**

- Storage class lives in `helmrelease.yaml` values (e.g., `persistence.storageClass: csi-hostpath-sc`)
- Commit 2 edits the HelmRelease value
- After Flux reconcile: Helm chart's rendered PVC template matches the existing longhorn PVC, no recreate

**authentik special handling:**
- Uses bitnami/postgresql StatefulSet
- PVC name `data-authentik-postgresql-0` is fixed by `volumeClaimTemplate`, immutable
- Restore CR's `target.pvc.name` MUST match exactly: `data-authentik-postgresql-0`
- Namespace `authentik` already has `kopiur.home-operations.com/privileged-movers: "true"`
- Restore CR mover `securityContext.runAsUser: 1001, runAsGroup: 1001` matches the Bitnami postgres UID/GID recorded in snapshots

### B. Raw deployment + PVC manifest apps

**prowlarr, radarr, sonarr, qbittorrent, sabnzbd, tdarr**

- PVC defined directly in `k3s/applications/<app>/pvc.yaml`
- Commit 2 edits `pvc.yaml` directly
- Flux applies the manifest directly, no Helm reconcile dance

**Multi-PVC apps:**
- qbittorrent: 2 PVCs (qbittorrent-config, gluetun-config)
- sabnzbd: 2 PVCs (sabnzbd-config, gluetun-config)
- tdarr: 2 PVCs (tdarr-server-data, tdarr-node-config)
- Each PVC needs its own Restore CR (single Restore CR per source PVC)
- Both PVCs migrate in lockstep — gluetun-config must be ready before app pod starts
- **Split policies (PR #318):** qbittorrent and sabnzbd each have separate snapshot policies per source PVC (`qbittorrent-config` / `qbittorrent-gluetun-config`, `sabnzbd-config` / `sabnzbd-gluetun-config`). The Restore CR's `source.fromPolicy.name` MUST reference the **split** policy that matches the source PVC — not the pre-split umbrella name. Verify per Constraint 7.

### Restore CR template (per PVC source, per namespace)

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: <app>-<pvc>-longhorn-migration
  namespace: <ns>
spec:
  source:
    fromPolicy:
      name: <policy-name>      # exact snapshot policy name
      offset: 0
  target:
    pvc:
      name: <exact-pvc-name>   # must match chart/pvc.yaml name
      storageClassName: longhorn
      accessModes: [ReadWriteOnce]
      capacity: <same-as-current>
  credentialProjection:
    enabled: true              # ClusterRepository 'nas' secret lives in kopiur-system
  mover:
    inheritSecurityContextFrom:
      snapshot: {}             # preserves UID/GID from backup
    cache:
      capacity: 1Gi
      storageClassName: local-path
      mode: Ephemeral
  failurePolicy:
    backoffLimit: 2
    activeDeadlineSeconds: 1800
  policy:
    onMissingSnapshot: Fail
```

### Per-app Restore CR count

| App | Restore CRs | PVC names |
|-----|-------------|-----------|
| prowlarr | 1 | prowlarr-config |
| radarr | 1 | radarr-config |
| sonarr | 1 | sonarr-config |
| pihole | 1 | pihole |
| qbittorrent | 2 | qbittorrent-config, gluetun-config |
| sabnzbd | 2 | sabnzbd-config, gluetun-config |
| tdarr | 2 | tdarr-server-data, tdarr-node-config |
| authentik | 1 | data-authentik-postgresql-0 |
| **Total** | **11** | |

## Data flow

```
kopiur snapshot (csi-hostpath-snapclass VolumeSnapshot)
    │
    │ 1. operator: kubectl apply -f migration/restore.yaml
    ▼
Restore CR (kopiur operator)
    │
    │ 2. resolves source: latest Snapshot CR from SnapshotPolicy
    │ 3. creates target PVC on longhorn StorageClass
    │ 4. launches mover Job:
    │    - mounts source snapshot (CSI)
    │    - mounts target PVC (RWO longhorn)
    │    - reads kopia repository, writes restored data
    │    - inherits UID/GID from snapshot metadata
    ▼
target PVC: <name> bound on longhorn, populated with snapshot data
    │
    │ 5. operator: kubectl scale deploy/<app> --replicas=1 (or HelmRelease update)
    │ 6. commit 2 lands: storageClassName → longhorn in HelmRelease or pvc.yaml
    │ 7. Flux reconciles: chart's PVC template matches existing PVC
    ▼
app running on longhorn PVC, identical data, RWO bound by pod
    │
    │ 8. commit 3 lands: volumeSnapshotClassName → longhorn-snapclass
    ▼
next hourly snapshot uses longhorn VolumeSnapshotClass
```

## Pre-flight verification (per app, before Commit 1)

1. `kubectl get snapshots -n <ns> -l kopiur.home-operations.com/policy-name=<policy>` → most recent has `status: ReadyToUse: true`
2. If no recent successful snapshot → **pause**, fix kopiur/policy first
3. `kubectl get pvc -n <ns> <pvc> -o jsonpath='{.spec.storageClassName}'` → confirm `csi-hostpath-sc`
4. `kubectl get volumesnapshot -n <ns>` → check for stale snapshots holding `pvc-as-source-protection` finalizers; clear before applying Restore CR (gatus #307 lesson)
5. `kubectl get restore -n <ns>` → confirm no other Restore CR is in-flight in this namespace
6. **(Constraint 7)** `kubectl get snapshotpolicy -n <ns> <policy> -o jsonpath='{.spec.sources}' | yq '. | length'` → exactly `1`. For multi-source policies, **split first** and wait one snapshot cycle. For qbittorrent/sabnzbd, verify the Restore CR references the *split* policy name (`qbittorrent-config`, `qbittorrent-gluetun-config`, etc.), not the pre-split umbrella name.
7. **(Constraint 7)** `kubectl get snapshots -n <ns> -l kopiur.home-operations.com/config=<policy> -o jsonpath='{.items[-1:].status.resolved.sources}' | yq '. | length'` → exactly `1`, and that source's `pvc` matches the source PVC name for this Restore CR.
8. **(Constraint 4)** `grep -E "migration/" k3s/applications/<app>/kustomization.yaml` → expected empty. If non-empty, fix the kustomization first (separate fix PR, matching the portainer #312 precedent) before running the migration.
9. **(Constraint 8 — controller-load awareness)** Migrations churn Flux, kopiur, snapshot, and Longhorn controllers. Single-node k3s+kine (SQLite) has a write-concurrency ceiling. Check for current symptoms (`kubectl get events -A --field-selector reason=Backoff`) and defer or pause kopiur snapshot schedules if the cluster is already under load.

## Per-commit verification

| After commit | Verification |
|--------------|--------------|
| Commit 1 (Restore CR applied) | `kubectl get restore -n <ns> -o jsonpath='{.items[*].status.phase}'` → `Completed`<br>`kubectl get pvc -n <ns> <name> -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}'` → `longhorn\tBound`<br>**Content check (Constraint 6):** exec/run a throwaway pod against the restored PVC, confirm `du -sh` is in the right ballpark for the source snapshot's `sizeBytes` and file mtimes predate the migration — don't trust `Completed` alone |
| Commit 2 (storageClassName change) | `kubectl get helmrelease -n <ns> <name>` → `Ready: True`<br>or for raw apps: `kubectl get pvc -n <ns> <name> -o jsonpath='{.spec.storageClassName}'` → `longhorn`<br>App pod running and healthy: `kubectl get pods -n <ns>` |
| Commit 3 (snapshot policy update) | `kubectl get snapshotpolicy -n <ns> <name> -o jsonpath='{.spec.volumeSnapshotClassName}'` → `longhorn-snapclass`<br>Wait for next hourly snapshot, verify it succeeds |

## Error handling

### Restore CR fails or stalls

0. **Before anything else: `kubectl scale deployment <app> -n <ns> --replicas=0` and leave it there** (Constraint 5). Do not let the app's own manifest reprovision a fresh empty PVC in place of the one that was supposed to be restored.
1. `kubectl delete restore -n <ns> <name>` (clears operator locks)
2. Investigate: stale finalizers? missing snapshot? mover Job crash? **Single-source policy?** (Constraint 7 — multi-source silently drops sources; the restore's source data may be the wrong PVC entirely.)
3. Fix root cause
4. Re-apply same Restore CR (idempotent)
5. Do not proceed to the next app's migration task, and do not scale the app back up, until this Restore CR reaches `Completed` and passes content verification — or a human explicitly decides to abandon this PVC's migration.

### Pod won't start on longhorn PVC

- Check UID/GID on restored files via debug pod
- Compare to what chart's initContainer chowns to
- Adjust `mover.inheritSecurityContextFrom.snapshot: {}` or run a chown job manually

### Commit 2 causes Flux conflict

- **Do NOT `kubectl delete helmrelease`, `kubectl delete pvc <restored>`, or `kubectl delete deployment` to fix this** (Constraint 9). Helm-controller GC will permanently destroy the restored data.
- **First step: `grep -rn "csi-hostpath-sc" k3s/applications/<app>/`** — the most likely cause is a stale `migration/*.yaml` listed in `kustomization.yaml` resources re-applying the old storageClassName on every reconcile (portainer #312 lesson). Fix the kustomization (separate fix PR) before continuing.
- If the repo is clean, restart controllers in this order, each a pod delete (not a resource delete): `flux reconcile kustomization apps --with-source`, then `kubectl delete pod -n flux-system -l app=helm-controller`, then `kubectl delete pod -n flux-system -l app=kustomize-controller`, then wait for the next reconcile interval.

### Restore CR completes but PVC contains wrong PVC's data

Symptom: Restore reaches `Completed`, PVC is on longhorn, size and mtimes look plausible — but the per-app content check (Constraint 6) fails because the restored data belongs to a different PVC.

Cause: the source SnapshotPolicy was multi-source and silently dropped all but the first source (Constraint 7).

Fix:
1. Do not scale the app back up (Constraint 5).
2. Delete the longhorn PVC and the Restore CR.
3. Split the source policy per source PVC (one policy per source), wait one snapshot cycle, re-run the pre-flight Constraint 7 check.
4. Re-apply the Restore CR using the split policy.
5. Verify content per Constraint 6.

### Reverse-recovery: app discovered on a blank PVC after the fact

If post-migration verification reveals the app is running on a freshly-reprovisioned empty PVC (the sabnzbd-config incident): see Constraint 10. Recovery uses `spec.source.snapshotRef` pinned to a pre-incident `Discovered` Snapshot CR, not `fromPolicy`.

## Rollback path

- Data is in kopiur snapshot for at least 24h (`keepHourly: 24`)
- Old csi-hostpath-sc PVC is deleted before Restore runs — cannot revert in-place
- Recovery: delete longhorn PVC, re-apply Restore CR with `offset: 1` (previous snapshot), or restore from backup
- For raw-deployment apps: temporarily revert `pvc.yaml` `storageClassName: csi-hostpath-sc` and restore PVC manually from snapshot via a fresh Restore to csi-hostpath-sc

## Batch ordering (Easy-first)

### Batch 1 — media namespace (3 PRs)
- PR 1: `feat(prowlarr): migrate prowlarr-config PVC to longhorn`
- PR 2: `feat(radarr): migrate radarr-config PVC to longhorn`
- PR 3: `feat(sonarr): migrate sonarr-config PVC to longhorn`
- Risk: minimal — single PVC, LinuxServer PUID 1027, no privileged mover
- Verification gate: each app's WebUI loads, no data loss

### Batch 2 — qbittorrent + sabnzbd (2 PRs)
- PR 4: `feat(qbittorrent): migrate qbittorrent-config + gluetun-config to longhorn`
- PR 5: `feat(sabnzbd): migrate sabnzbd-config + gluetun-config to longhorn`
- Risk: medium — multi-PVC, must lockstep both
- Verification gate: torrent client connects, downloads work, VPN tunnel up

### Batch 3 — tdarr (1 PR)
- PR 6: `feat(tdarr): migrate tdarr-server-data + tdarr-node-config to longhorn`
- Risk: medium — multi-PVC + privileged mover namespace
- Namespace already has `kopiur.home-operations.com/privileged-movers: "true"`
- Verification gate: tdarr-server boots, tdarr-node registers, scan a test library

### Batch 4 — pihole + authentik (2 PRs)
- PR 7: `feat(pihole): migrate pihole PVC to longhorn`
  - HelmRelease `persistence.storageClass` change
  - Namespace already has privileged-movers annotation
  - Verification: DNS resolves, admin UI loads
- PR 8: `feat(authentik): migrate data-authentik-postgresql-0 PVC to longhorn`
  - **Most complex**: bitnami/postgresql StatefulSet, immutable volumeClaimTemplate
  - Verification: authentik login works, postgresql DB intact

## Optional cleanup follow-ups (per app)

For raw-deployment apps: verify `k3s/applications/<app>/kustomization.yaml` doesn't list stale `migration/` files. If it does, separate fix PR removing them from the resources list.

## Risks tracked

- Backup snapshots may still be failing silently — verify before each Restore CR
- HelmRelease PVC recreation race during storage class change — watch Flux logs
- StatefulSet PVC name mismatch breaks migration — Restore CR's `target.pvc.name` must be exact
- CSI hostpath provisioner timeout on snapshot restores — affects backup system, not the migration flow itself, but blocks step 1 (need working snapshot)
- **Multi-source SnapshotPolicy silently drops sources** — Constraint 7 mitigates; the policy must be single-source or split per source PVC before any Restore CR runs
- **App reprovisioning silently on blank PVC after failed Restore** — Constraint 5 (hard stop, leave app at scale 0) and Constraint 8 (verify snapshot before delete) mitigate
- **k3s+kine controller-load ceiling** — Constraint 8's controller-load awareness step mitigates; defer migrations when cluster is already under heavy controller churn
- **Stale `migration/` files in kustomization.yaml** — Constraint 4 (extended) mitigates; pre-flight grep before each migration
- **HelmRelease/PVC deletion to "fix" dry-run destroys data** — Constraint 9 mitigates; grep the repo first, restart controller pods only

## Out of scope (deferred)

- 4 local-path PVCs (Prometheus DB, Loki, Tempo, sabnzbd-downloads) — separate future migration
- Kopiur system-level fixes
- smb-media PVCs (different StorageClass by design)

## Related references

- Past migrations:
  - gatus: PR #307
  - headlamp: PR #309
  - portainer: PR #310, cleanup PR #312
  - monitoring: PR #311 (alertmanager + grafana, multi-PVC in one PR)
- Established pattern references:
  - `k3s/applications/headlamp/migration/restore.yaml` — canonical Restore CR example
  - `k3s/applications/portainer/migration/restore.yaml` — second canonical example
- Lessons-learned docs in repo memory (claude-mem):
  - `csi-hostpath-to-longhorn-restore-cr.md` — credentialProjection + inheritSecurityContextFrom required
  - `kopiur-privileged-mover.md` — apps with chart-init root-owned files need namespace annotation
  - `kopiur-repo-per-namespace.md` — kopiur-repo PV/PVC must exist per namespace
- Hardening precedents driving Constraints 7-10:
  - **Sabnzbd-config data loss (PR #324):** Restore CR failed, source PVC deleted, app reprovisioned blank PVC, ran ~90 minutes on blank config before noticed. Corrective plan: `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md`. Established Constraint 5 (hard stop) and Constraint 6 (verify content).
  - **qbittorrent-gluetun-config contamination (PR #326):** Multi-source SnapshotPolicy silently dropped all but first source; gluetun-config got qbittorrent-config's data. Established Constraint 7 (single-source precondition).
  - **Portainer data loss (PR #310):** HelmRelease deleted to "fix" dry-run; helm-controller GC destroyed chart-managed PVC. Established Constraint 9 (never delete user-facing resources).
  - **Portainer dry-run conflict (PR #312):** Stale `migration/pvc.yaml` listed in kustomization resources caused Flux to keep re-applying the old storageClassName. Extended Constraint 4 and added the "grep first" rule in Constraint 9.

- Lessons-learned docs in repo memory (claude-mem) — additional:
  - `kopiur-multi-source-snapshot-policy-silently-drops-sources.md` — the bug behind Constraint 7
  - `csi-hostpath-to-longhorn-migration-bundled-changes.md` — why all three commits must land together
  - `sabnzbd-config-data-loss-2026-08-21.md` — incident timeline behind Constraints 5/6/10
  - `k3s-kine-scalability-ceiling.md` — the controller-load context behind Constraint 8's load awareness
