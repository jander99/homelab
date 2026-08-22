# Finish csi-hostpath-sc → Longhorn PVC Migration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the remaining 11 csi-hostpath-sc PVCs across 8 apps to Longhorn storage class with zero data loss, using the established Restore CR pattern.

**Architecture:** One PR per app (8 PRs total). Each PR contains 3 ordered commits: (1) operator-applied Restore CR that copies data from kopiur snapshot to a fresh longhorn PVC, (2) storageClassName change in the source manifest (HelmRelease or pvc.yaml), (3) snapshot policy snapclass update to longhorn-snapclass. Apps execute in easy-first batches (media → qbittorrent/sabnzbd → tdarr → pihole/authentik).

**Tech Stack:** Kubernetes 1.32, k3s, Flux v2, HelmRelease, Helm v3, Kustomize, kopiur (snapshot/restore operator), Longhorn CSI, csi-hostpath-snapclass → longhorn-snapclass, SOPS-encrypted secrets.

**Spec:** `docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md`

## Global Constraints

1. **No data loss.** Every migration preserves data via kopiur snapshot → Restore CR → fresh longhorn PVC.
2. **Backup health must be verified before each Restore CR.** If latest snapshot for an app is missing/failed, pause and fix kopiur/policy first.
3. **Restore CR is operator-applied (`kubectl apply -f`), never listed in `kustomization.yaml` resources.** Listing it there causes Flux to reapply it on every reconcile and fights the HelmRelease-managed PVC.
4. **Migration PVCs in `migration/` directories that have served their purpose must be removed from `kustomization.yaml` resources lists** after the migration succeeds (portainer #312 lesson). Imperative PVC manifests with stale storageClassName conflict with the chart-managed PVC.
5. **All work happens on a feature branch in a worktree**, not on master. Per AGENTS.md: never offer completed work on master unless prompted.
6. **Each PR must reference the issue/PR it closes or relates to** in the body, and link back to the spec doc.
7. **Commit messages follow Conventional Commits:** `feat(<scope>): <description>`, `fix(<scope>): <description>`, `docs(<scope>): <description>`.
8. **PR titles mirror the squash commit message** for clean history.
9. **A Restore CR that does not reach `Completed` is a hard stop, not a deferred TODO.** Scale the app to 0 and leave it down. Do not scale it back up on the untouched/auto-provisioned PVC, and do not move on to the next app's migration task, until the restore is either fixed and re-run successfully, or the migration for that PVC is explicitly abandoned by the human partner (not by the agent). *Why this exists:* the sabnzbd-config restore failed during this migration (multi-source SnapshotPolicy bug), the failure was written into a task report as "BLOCKED" and work continued to other apps/tasks, and the app's own manifest silently reprovisioned a brand-new empty PVC — sabnzbd ran on a blank config for ~90 minutes before anyone noticed (see `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md`). A written status note is not a safeguard; a scaled-to-0 deployment is.
10. **A `Completed` Restore CR is not itself proof the data is right — verify content, not just phase.** At minimum: compare restored size against the source snapshot's `status.stats.sizeBytes`, and spot-check that a known file/directory has a plausible pre-migration mtime (not "today"). See Task 3 Step 5 of the sabnzbd recovery plan for a worked example using a throwaway busybox pod. The per-app **content verification table** below lists specific files/directories each restored PVC must (and must not) contain — use that, not just a generic `du -sh`.
11. **Single-source snapshot policy is a precondition, not a guideline.** A kopiur `SnapshotPolicy` with multiple `sources:` only captures the **first** source; the rest are silently dropped, and the Restore CR that follows will write the wrong PVC's data into the target (silent corruption — qbittorrent-gluetun-config got qbittorrent-config's data, sabnzbd-config got nothing useful). For every migration task: verify the policy has exactly one `sources:` entry AND the most recent Snapshot CR's `status.resolved.sources` lists exactly one source matching the source PVC name. If either fails, the migration is BLOCKED until the policy is split per app/PVC. (See Task 0 Step 1a for the exact check.)
12. **Source PVC deletion requires a verified, recently-completed snapshot for that exact source PVC.** The order is: scale down → verify the latest snapshot has `status.phase: Succeeded` AND `status.resolved.sources` matches the source PVC name → delete source PVC → apply Restore CR. Never delete the source PVC based on a stale or empty snapshot check. (Sabnzbd-config incident: source PVC deleted, restore failed, app reprovisioned blank PVC, blank state ran for ~90 minutes.)
13. **Never `kubectl delete helmrelease`, `kubectl delete pvc <restored>`, or `kubectl delete deployment` to recover from a Flux dry-run failure or stuck-reconcile.** Helm-controller GC will garbage-collect the chart-managed PVC and permanently destroy the restored data (portainer #310). Safe recovery tools, in order: (1) `flux reconcile kustomization apps --with-source`, (2) `kubectl delete pod -n flux-system -l app=helm-controller`, (3) `kubectl delete pod -n flux-system -l app=kustomize-controller`, (4) wait for the next reconcile interval. **If a dry-run shows an unexpected value, FIRST `grep -rn <value> k3s/applications/<app>/` to find a stale `migration/` resource listing the old storageClassName.** That was the actual portainer #312 root cause — controller restarts never fix a conflict that comes from the repo.
14. **Reverse-recovery procedure (post-incident):** if you discover an app is running on a fresh/empty PVC after a migration completed (or after a failed/abandoned restore), the recovery is a new Restore CR pinned via `spec.source.snapshotRef` to the last known-good **Discovered** Snapshot CR for that source path (NOT `fromPolicy` — the policy's own post-incident scheduled snapshots are of the blank state and will silently restore nothing useful). Worked example: `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md` (the entire plan is a corrective follow-up to this constraint).

## Verification Standards

These commands MUST pass before marking any task complete. Run them, read the output, confirm.

```bash
# Per-app snapshot health (after Task 0 and before each migration task)
# NOTE: kopiur Snapshot CRs use label `kopiur.home-operations.com/config=<policy>`
# (not `policy-name` as documented elsewhere) and `status.phase` (not
# `ReadyToUse`). Mapped from VolumeSnapshot convention.
kubectl get snapshots -n <ns> --selector=kopiur.home-operations.com/config=<policy> --sort-by=.metadata.creationTimestamp | tail -5

# To check ReadyToUse status, inspect:
kubectl get snapshots -n <ns> --selector=kopiur.home-operations.com/config=<policy> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}' | tail -5

# Per-app Restore CR status (after Commit 1 of each migration task)
kubectl get restore -n <ns> -o jsonpath='{.items[*].status.phase}{"\n"}'

# Per-app PVC state (after Commit 1 and Commit 2)
kubectl get pvc -n <ns> <pvc> -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'

# Per-app HelmRelease (HelmRelease apps only)
kubectl get helmrelease -n <ns> <hr-name>

# Per-app pod health (after Commit 2)
kubectl get pods -n <ns> -o wide

# Per-app snapshot policy snapclass (after Commit 3)
kubectl get snapshotpolicy -n <ns> <policy> -o jsonpath='{.spec.volumeSnapshotClassName}{"\n"}'

# Content verification (after Restore CR reaches Completed — Constraint 10).
# `Completed` phase alone is not sufficient; confirm the bytes and the
# mtimes actually look like the pre-migration data, not a fresh/empty PVC.
kubectl get restore -n <ns> <restore-name> -o jsonpath='{.status.resolved.kopiaSnapshotID}{"\n"}'
kubectl get snapshots -n <ns> -l kopiur.home-operations.com/config=<policy> -o jsonpath='{.items[-1:].status.stats.sizeBytes}{"\n"}'
kubectl run <app>-restore-check --restart=Never -n <ns> --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"check","image":"busybox:1.36","command":["sh","-c","du -sh /data; find /data -maxdepth 2 -printf \"%TY-%Tm-%Td %p\\n\" | sort | tail -10"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}],"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"<pvc>"}}]}}'
# then: kubectl logs <app>-restore-check -n <ns>; kubectl delete pod <app>-restore-check -n <ns>

### Per-app content verification (Constraint 10, made specific)

Generic `du -sh` + `find` confirms size and mtimes but not *content identity*. For multi-PVC apps especially (qbittorrent, sabnzbd), a restored PVC could be the right size, on longhorn, with plausible mtimes, and still contain the *wrong* PVC's data — that's exactly what happened with `qbittorrent-gluetun-config` (got qbittorrent-config data, gluetun regenerated its tunnel state so the corruption was invisible). Each restored PVC must contain the expected app data and not the wrong app's data.

| PVC | Must contain | Must NOT contain | How to verify |
|-----|--------------|------------------|---------------|
| `prowlarr-config` | `config.xml`, `prowlarr.db`, mtimes predating migration | empty `prowlarr.db` | `find /config -maxdepth 2 -type f \| head` |
| `radarr-config` | `config.xml`, `radarr.db`, mtimes predating migration | empty `radarr.db` | `find /config -maxdepth 2 -type f \| head` |
| `sonarr-config` | `config.xml`, `sonarr.db`, mtimes predating migration | empty `sonarr.db` | `find /config -maxdepth 2 -type f \| head` |
| `qbittorrent-config` | qBittorrent config (`qBittorrent.conf`, `profiles/`), mtimes predating migration | gluetun config (`wg0.conf`, `openvpn/`) | `ls /config/qBittorrent.conf /config/profiles/` |
| `qbittorrent-gluetun-config` | gluetun config (regenerated tunnel state, `openvpn/` or `wireguard/` after first start) | qBittorrent app files (`qBittorrent.conf`) | `ls /gluetun` — gluetun regenerates tunnel state on first start, so freshly-restored config may look sparse but must not contain app data |
| `sabnzbd-config` | `sabnzbd.ini` with realistic `[section]` count (≥25 sections for a real install vs ~15-20 for blank), `admin/` (history DB), `logs/` | empty `sabnzbd.ini` (the 44KB+ file size from the real config is the smoking gun) | `grep -c '^\[' /config/sabnzbd.ini; ls /config/admin/ /config/logs/` |
| `sabnzbd-gluetun-config` | gluetun config | sabnzbd app files | `ls /gluetun` |
| `tdarr-server-data` | tdarr server config + DBs | empty `/config` | `ls /tdarr-server/config` |
| `tdarr-node-config` | tdarr-node config | empty config | `ls /tdarr-node/config` |
| `pihole` | `pihole-FTL.db`, `gravity.db`, `setupVars.conf` | empty databases | `ls /etc/pihole/pihole-FTL.db /etc/pihole/gravity.db` |
| `data-authentik-postgresql-0` | PG data dir with `PG_VERSION`, populated `base/`, mtimes predating migration | empty data dir | `ls /var/lib/postgresql/data/PG_VERSION /var/lib/postgresql/data/base/ \| head` |

For each "must NOT contain" row, if the check fails the PVC is silently contaminated and **Constraint 9 applies**: do not scale the app back up; investigate before proceeding (Constraint 13 — don't delete resources to recover; restart controller pods and re-check the source snapshot policy).

The busybox throwaway pattern above works for any of these — change the mount path and the `ls` / `find` / `grep` to match the row in the table.
```

---

## Task 0: Preflight — verify backup health across all 8 apps

**Why first:** Per the constraint that backup health must be verified before each Restore CR. If snapshots are failing for any app, that app's migration must wait. This task surfaces the baseline before any work begins.

**Files:** None modified — read-only verification.

**Interfaces:** Produces a status report: which apps have working recent snapshots, which need backup-system fixes first.

- [ ] **Step 1: Check most recent snapshot for each of the 8 namespaces**

Run for each app namespace (`prowlarr`/`radarr`/`sonarr` use namespace `media`; `pihole` uses `pihole`; `authentik` uses `authentik`; `qbittorrent`, `sabnzbd`, `tdarr` use their own namespaces):

```bash
for ns in media media media pihole authentik qbittorrent sabnzbd tdarr; do
  case "$ns" in
    media) apps="prowlarr radarr sonarr" ;;
    *) apps="$ns" ;;
  esac
  for app in $apps; do
    echo "=== $ns / $app ==="
    kubectl get snapshots -n "$ns" --selector=kopiur.home-operations.com/config="$app" --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -3
  done
done
```

Note any app where the most recent snapshot is missing, `status.phase != Succeeded`, or older than 2 hours. (kopiur Snapshot uses `status.phase` not `ReadyToUse`.)

- [ ] **Step 1a: Verify each policy is single-source (Constraint 11)**

A kopiur `SnapshotPolicy` with multiple `sources:` only captures the **first** source — rest are silently dropped (qbittorrent-gluetun-config + sabnzbd-config both got the wrong PVC's data because of this). For every policy that will back a Restore CR:

```bash
# 1. Policy has exactly 1 source declared:
kubectl get snapshotpolicy -n <ns> <policy> -o jsonpath='{.spec.sources}' | yq '. | length'
# Expected: 1

# 2. The most recent Snapshot CR's resolved sources match exactly one PVC
#    (and that PVC is the source PVC for the upcoming Restore):
kubectl get snapshots -n <ns> -l kopiur.home-operations.com/config=<policy> \
  -o jsonpath='{.items[-1:].status.resolved.sources}' | yq '. | length'
# Expected: 1
```

For qbittorrent and sabnzbd: the policies were already split (PR #318). Each Restore CR targets the split policy that matches its source PVC (`qbittorrent-config` → policy `qbittorrent-config`, `qbittorrent-gluetun-config` → policy `qbittorrent-gluetun-config`, same for sabnzbd). Verify the **split** policy name is correct for each Restore CR — don't reference the pre-split umbrella name. If a policy still has `sources: [pvc-a, pvc-b]`, **BLOCKED** — split it first, wait one snapshot cycle, and re-run this check.

- [ ] **Step 1b: Verify no stale `migration/` files in `kustomization.yaml` (Constraint 13)**

Portainer #312 lesson: old PVC manifests in `migration/` listed in `kustomization.yaml` resources get re-applied with the old storageClassName, fighting the new longhorn PVC in Flux dry-run.

```bash
for app in prowlarr radarr sonarr qbittorrent sabnzbd tdarr pihole authentik; do
  echo "=== $app ==="
  grep -E "migration/" "k3s/applications/$app/kustomization.yaml" 2>/dev/null || echo "  (no migration/ entries)"
done
```

Expected: no `migration/` entries in any `kustomization.yaml`. If any are listed, **fix the kustomization first** (separate fix PR per app, matches the portainer #312 precedent) before running the migration task.

- [ ] **Step 1c: Controller-load awareness (k3s+kine ceiling)**

Single-node k3s with kine/SQLite has a write-concurrency ceiling — when ~10+ controllers update coordination leases simultaneously, slow SQL cascades to API server handler timeouts → pod termination failures → CSI unmount errors (memory: `k3s-kine-scalability-ceiling`). Migrations create heavy controller churn (Flux, kopiur, snapshot, Longhorn). Before starting:

```bash
# Any current symptoms?
kubectl get events -A --field-selector reason=Backoff 2>/dev/null | tail -10
kubectl get pods -n kube-system -l k8s-app=kine -o wide 2>/dev/null
```

If `Backoff` events are accumulating or the kine pod has restarted recently, **defer the migration window** or suspend kopiur snapshot schedules for the duration:

```bash
# Temporarily pause kopiur snapshot schedules (one-off):
kubectl patch snapshotschedule -A --type merge -p '{"spec":{"schedule":"0 0 1 1 *"}}' 2>/dev/null
# ...run the migration...
# Restore schedules afterward.
```

- [ ] **Step 2: Check Restore CR conflicts**

Verify no Restore CRs are already in-flight that could conflict:

```bash
kubectl get restore -A 2>/dev/null
```

Expected: empty list, or only Completed-phase Restore CRs from prior migrations (gatus, headlamp, portainer, monitoring).

- [ ] **Step 3: Check Flux and kopiur-system health**

```bash
kubectl get pods -n flux-system
kubectl get pods -n kopiur-system
```

Expected: All pods Running. If any are CrashLoopBackOff or Pending, pause and fix.

- [ ] **Step 4: Document the per-app snapshot status**

For each of the 8 apps, write down:
- Most recent snapshot creation timestamp
- Most recent snapshot `status.phase` (Succeeded/Failed)
- Backup policy name (for use in Task N Restore CRs) — verify it's the split policy name (Step 1a) for qbittorrent/sabnzbd
- Most recent snapshot's `status.resolved.sources` — verify it matches the source PVC name (Step 1a)

Expected outcome: each app has a recent (≤2h old) `Succeeded` snapshot whose resolved sources match the source PVC.

If any app has a missing/failed/old snapshot:
- Investigate the snapshot policy: `kubectl get snapshotpolicy -n <ns> <policy> -o yaml`
- Check mover Jobs: `kubectl get jobs -n <ns> -l app=kopiur-mover`
- Common cause (per past session S108): CSI hostpath provisioner timing out on restore operations; need a separate fix PR before proceeding
- Pause this plan; do NOT proceed to migration tasks until backup health is restored

- [ ] **Step 5: Commit preflight notes (no code change)**

If you recorded findings in a markdown file, commit it to a feature branch for tracking:

```bash
git checkout -b feat/migration-preflight-notes
# ...create docs/operations/2026-08-20-migration-preflight.md with findings...
git add docs/operations/2026-08-20-migration-preflight.md
git commit -m "docs(migration): preflight backup health check for csi-hostpath → longhorn batch"
```

(If preflight is clean with no findings worth committing, skip this step.)

---

## Batch 1: media namespace (prowlarr, radarr, sonarr)

These are the simplest migrations: single PVC each, LinuxServer PUID 1027 PGID 100, no privileged mover namespace annotation needed. Each migration is its own PR.

---

### Task 1: prowlarr migration

**Files:**
- Create: `k3s/applications/prowlarr/migration/restore.yaml`
- Modify: `k3s/applications/prowlarr/pvc.yaml:1-12`
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-prowlarr.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `prowlarr` in namespace `media`, source PVC `prowlarr-config` (2Gi)
- Produces: longhorn PVC `prowlarr-config` bound and populated; snapshot policy using `longhorn-snapclass`

- [ ] **Step 1: Create worktree for prowlarr PR**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/prowlarr-longhorn -b feat/prowlarr-longhorn origin/master
cd .worktrees/prowlarr-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CR**

Create `k3s/applications/prowlarr/migration/restore.yaml` with this content (adapted from headlamp canonical example at `k3s/applications/headlamp/migration/restore.yaml`):

```yaml
---
# Restore CR for the prowlarr csi-hostpath-sc → longhorn migration.
#
# Operator-applied (NOT in kustomization.yaml). Run with `kubectl apply -f`
# once after scaling prowlarr to 0 replicas. Matches the pattern in
# gatus/migration/, headlamp/migration/, portainer/migration/.
#
# Delete manually if desired:
#   kubectl delete restore -n media prowlarr-longhorn-migration
#
# Pre-conditions (operator must do before applying):
#   - prowlarr deployment scaled to 0 replicas (releases RWO on old PVC).
#   - Stale csi-hostpath-snapclass VolumeSnapshots cleared (they hold
#     pvc-as-source-protection finalizers on the source PVC).
#   - The old csi-hostpath-sc PVC `prowlarr-config` deleted (Restore's
#     target.pvc would otherwise hit a name conflict; data is safe in kopia).
#
# Post-conditions:
#   - PVC `prowlarr-config` exists, bound on `longhorn`, populated with snapshot.
#   - prowlarr deployment scaled back to 1 replica binds to longhorn PVC.
#   - Restored files are owned by UID 1027 GID 100 (LinuxServer prowlarr
#     PUID/PGID), matching the policy's recorded snapshot metadata.
#
# credentialProjection: REQUIRED. ClusterRepository `nas` secret lives in
# kopiur-system, not media. Without `credentialProjection.enabled: true`
# the Restore stalls with MissingCredentialsSecret.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: prowlarr-longhorn-migration
  namespace: media
spec:
  source:
    fromPolicy:
      name: prowlarr
      offset: 0
  target:
    pvc:
      name: prowlarr-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 2Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:

```bash
git add k3s/applications/prowlarr/migration/restore.yaml
git commit -m "feat(prowlarr): add Restore CR for csi-hostpath-sc → longhorn migration"
```

- [ ] **Step 3: Apply Restore CR imperatively (operator action)**

Pre-conditions:
```bash
kubectl scale deploy/prowlarr -n media --replicas=0
# Wait for pod to terminate:
kubectl wait pod -l app=prowlarr -n media --for=delete --timeout=60s
# Clear stale VolumeSnapshots that hold pvc-as-source-protection finalizers:
kubectl get volumesnapshot -n media -l kopiur.home-operations.com/policy-name=prowlarr
# If any are stuck Pending without status, patch out the finalizer:
# kubectl patch volumesnapshot <name> -n media --type merge -p '{"metadata":{"finalizers":null}}'
# Delete the old PVC:
kubectl delete pvc -n media prowlarr-config
```

Apply:
```bash
kubectl apply -f k3s/applications/prowlarr/migration/restore.yaml
```

Wait for completion:
```bash
kubectl get restore -n media prowlarr-longhorn-migration -w
# Wait until phase=Completed (typically 2-10 minutes for 2Gi PVC)
```

Verify PVC:
```bash
kubectl get pvc -n media prowlarr-config -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
```

If the Restore stalls in `Pending` or fails, see the **Failure handling** section below.

- [ ] **Step 4: Write Commit 2 — pvc.yaml storageClassName change**

Edit `k3s/applications/prowlarr/pvc.yaml`. Change the `prowlarr-config` PVC block's `storageClassName` from `csi-hostpath-sc` to `longhorn`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prowlarr-config
  namespace: media
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn   # was: csi-hostpath-sc
  resources:
    requests:
      storage: 2Gi
```

Stage and commit:
```bash
git add k3s/applications/prowlarr/pvc.yaml
git commit -m "feat(prowlarr): switch prowlarr-config storageClassName to longhorn"
```

Flux reconciles within ~1m. Verify:
```bash
kubectl get pvc -n media prowlarr-config -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
```

Scale prowlarr back to 1 replica:
```bash
kubectl scale deploy/prowlarr -n media --replicas=1
kubectl wait pod -l app=prowlarr -n media --for=condition=Ready --timeout=120s
```

Verify the app is functional:
```bash
kubectl get pods -n media -l app=prowlarr
# Expected: 1/1 Running
```

Hit the WebUI to confirm no data loss (the user's existing indexers, apps, settings should all be present):
```bash
# port-forward or use ingress depending on local DNS; if curl is available:
curl -sk https://prowlarr.homelab.properties/ping | head
```

- [ ] **Step 5: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-prowlarr.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`:

```yaml
  copyMethod: Snapshot
  # Migrated from csi-hostpath-snapclass to longhorn-snapclass in
  # feat/prowlarr-longhorn. The prowlarr-config PVC is now on the `longhorn`
  # StorageClass (PR prepping the move in pvc.yaml), so the CSI snapshot
  # must use the matching Longhorn VolumeSnapshotClass.
  volumeSnapshotClassName: longhorn-snapclass
```

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-prowlarr.yaml
git commit -m "feat(kopiur): switch prowlarr snapshot policy to longhorn-snapclass"
```

Verify:
```bash
kubectl get snapshotpolicy -n media prowlarr -o jsonpath='{.spec.volumeSnapshotClassName}{"\n"}'
# Expected: longhorn-snapclass
```

Wait for the next hourly snapshot and verify it succeeds:
```bash
# Find next scheduled time:
kubectl get snapshotpolicy -n media prowlarr -o jsonpath='{.spec.schedule}{"\n"}'
# Wait until that time, then:
kubectl get snapshots -n media --selector=kopiur.home-operations.com/config=prowlarr --sort-by=.metadata.creationTimestamp | tail -2
# Expected: status.phase shows Succeeded on the new snapshot (NOT ReadyToUse — kopiur uses phase)
kubectl get snapshots -n media --selector=kopiur.home-operations.com/config=prowlarr -o jsonpath='{range .items[-2:]}{.metadata.name}{"\t"}{.status.phase}{"\n"}'
```

- [ ] **Step 6: Cleanup follow-up — verify kustomization.yaml doesn't list migration/**

```bash
cat k3s/applications/prowlarr/kustomization.yaml
```

If the resources list includes `migration/restore.yaml`, `migration/pvc.yaml`, or any other migration artifact, remove those lines. (For prowlarr specifically, the kustomization does not currently list migration/, so this should be a no-op. Verify and move on.)

If a cleanup change is needed, commit:
```bash
git add k3s/applications/prowlarr/kustomization.yaml
git commit -m "fix(prowlarr): remove migration files from kustomization resources"
```

- [ ] **Step 7: Push branch and open PR**

```bash
git push -u origin feat/prowlarr-longhorn
gh pr create --base master --head feat/prowlarr-longhorn \
  --title "feat(prowlarr): migrate prowlarr-config PVC from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Closes the csi-hostpath-sc cleanup for prowlarr. See docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md.

Pattern matches gatus #307, headlamp #309, portainer #310/#312, monitoring #311.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

After merge, Flux reconciles within ~1m. Verify:
```bash
kubectl get pvc -n media prowlarr-config
kubectl get pods -n media -l app=prowlarr
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/prowlarr-longhorn
git branch -d feat/prowlarr-longhorn
```

---

### Task 2: radarr migration

**Files:**
- Create: `k3s/applications/radarr/migration/restore.yaml`
- Modify: `k3s/applications/radarr/pvc.yaml:1-12`
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-radarr.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `radarr` in namespace `media`, source PVC `radarr-config` (2Gi)
- Produces: longhorn PVC `radarr-config` bound and populated; snapshot policy using `longhorn-snapclass`

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/radarr-longhorn -b feat/radarr-longhorn origin/master
cd .worktrees/radarr-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CR**

Create `k3s/applications/radarr/migration/restore.yaml` with this content (mirror of prowlarr's restore.yaml; only the names differ):

```yaml
---
# Restore CR for the radarr csi-hostpath-sc → longhorn migration.
# Operator-applied. See prowlarr/migration/restore.yaml for the full header
# rationale; same pattern, same pre/post-conditions.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: radarr-longhorn-migration
  namespace: media
spec:
  source:
    fromPolicy:
      name: radarr
      offset: 0
  target:
    pvc:
      name: radarr-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 2Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/radarr/migration/restore.yaml
git commit -m "feat(radarr): add Restore CR for csi-hostpath-sc → longhorn migration"
```

- [ ] **Step 3: Apply Restore CR imperatively**

```bash
kubectl scale deploy/radarr -n media --replicas=0
kubectl wait pod -l app=radarr -n media --for=delete --timeout=60s
# Clear stale VolumeSnapshots if any:
kubectl get volumesnapshot -n media -l kopiur.home-operations.com/policy-name=radarr
kubectl delete pvc -n media radarr-config
kubectl apply -f k3s/applications/radarr/migration/restore.yaml
kubectl get restore -n media radarr-longhorn-migration -w
# Wait for phase=Completed
kubectl get pvc -n media radarr-config -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
```

- [ ] **Step 4: Write Commit 2 — pvc.yaml storageClassName change**

Edit `k3s/applications/radarr/pvc.yaml`. Change `radarr-config` PVC block's `storageClassName` from `csi-hostpath-sc` to `longhorn`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: radarr-config
  namespace: media
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn   # was: csi-hostpath-sc
  resources:
    requests:
      storage: 2Gi
```

Stage and commit:
```bash
git add k3s/applications/radarr/pvc.yaml
git commit -m "feat(radarr): switch radarr-config storageClassName to longhorn"
```

Flux reconciles. Scale radarr back:
```bash
kubectl get pvc -n media radarr-config -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
kubectl scale deploy/radarr -n media --replicas=1
kubectl wait pod -l app=radarr -n media --for=condition=Ready --timeout=120s
```

Verify WebUI:
```bash
curl -sk https://radarr.homelab.properties/ping | head
```

- [ ] **Step 5: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-radarr.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-radarr.yaml
git commit -m "feat(kopiur): switch radarr snapshot policy to longhorn-snapclass"
```

Verify:
```bash
kubectl get snapshotpolicy -n media radarr -o jsonpath='{.spec.volumeSnapshotClassName}{"\n"}'
# Expected: longhorn-snapclass
```

- [ ] **Step 6: Cleanup follow-up**

```bash
cat k3s/applications/radarr/kustomization.yaml
```

If migration/ files are listed in resources, remove them and commit. Otherwise no-op.

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/radarr-longhorn
gh pr create --base master --head feat/radarr-longhorn \
  --title "feat(radarr): migrate radarr-config PVC from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Same pattern as prowlarr (this PR), headlamp #309, portainer #310/#312. See docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

Verify:
```bash
kubectl get pvc -n media radarr-config
kubectl get pods -n media -l app=radarr
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/radarr-longhorn
git branch -d feat/radarr-longhorn
```

---

### Task 3: sonarr migration

**Files:**
- Create: `k3s/applications/sonarr/migration/restore.yaml`
- Modify: `k3s/applications/sonarr/pvc.yaml:1-12`
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sonarr.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `sonarr` in namespace `media`, source PVC `sonarr-config` (2Gi)
- Produces: longhorn PVC `sonarr-config` bound and populated; snapshot policy using `longhorn-snapclass`

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/sonarr-longhorn -b feat/sonarr-longhorn origin/master
cd .worktrees/sonarr-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CR**

Create `k3s/applications/sonarr/migration/restore.yaml`:

```yaml
---
# Restore CR for the sonarr csi-hostpath-sc → longhorn migration.
# Operator-applied. Same pattern as prowlarr/radarr (this batch), headlamp #309,
# portainer #310/#312. See prowlarr/migration/restore.yaml for the full header.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: sonarr-longhorn-migration
  namespace: media
spec:
  source:
    fromPolicy:
      name: sonarr
      offset: 0
  target:
    pvc:
      name: sonarr-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 2Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/sonarr/migration/restore.yaml
git commit -m "feat(sonarr): add Restore CR for csi-hostpath-sc → longhorn migration"
```

- [ ] **Step 3: Apply Restore CR imperatively**

```bash
kubectl scale deploy/sonarr -n media --replicas=0
kubectl wait pod -l app=sonarr -n media --for=delete --timeout=60s
kubectl get volumesnapshot -n media -l kopiur.home-operations.com/policy-name=sonarr
kubectl delete pvc -n media sonarr-config
kubectl apply -f k3s/applications/sonarr/migration/restore.yaml
kubectl get restore -n media sonarr-longhorn-migration -w
# Wait for phase=Completed
kubectl get pvc -n media sonarr-config -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
```

- [ ] **Step 4: Write Commit 2 — pvc.yaml storageClassName change**

Edit `k3s/applications/sonarr/pvc.yaml`. Change `sonarr-config` PVC block's `storageClassName` from `csi-hostpath-sc` to `longhorn`.

Stage and commit:
```bash
git add k3s/applications/sonarr/pvc.yaml
git commit -m "feat(sonarr): switch sonarr-config storageClassName to longhorn"
```

Scale sonarr back:
```bash
kubectl scale deploy/sonarr -n media --replicas=1
kubectl wait pod -l app=sonarr -n media --for=condition=Ready --timeout=120s
curl -sk https://sonarr.homelab.properties/ping | head
```

- [ ] **Step 5: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sonarr.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sonarr.yaml
git commit -m "feat(kopiur): switch sonarr snapshot policy to longhorn-snapclass"
```

- [ ] **Step 6: Cleanup follow-up**

Verify `k3s/applications/sonarr/kustomization.yaml` doesn't list migration/. Remove if it does, commit fix.

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/sonarr-longhorn
gh pr create --base master --head feat/sonarr-longhorn \
  --title "feat(sonarr): migrate sonarr-config PVC from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Same pattern as prowlarr/radarr (this batch), headlamp #309, portainer #310/#312.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

```bash
kubectl get pvc -n media sonarr-config
kubectl get pods -n media -l app=sonarr
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/sonarr-longhorn
git branch -d feat/sonarr-longhorn
```

---

## Batch 1 verification gate

After all three of prowlarr, radarr, sonarr are merged and Flux reconciled:

```bash
kubectl get pvc -n media -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
# Expected: all three config PVCs show storageClassName=longhorn, phase=Bound
kubectl get pods -n media -l 'app in (prowlarr,radarr,sonarr)'
# Expected: all Running
```

If any migration fails, **stop** before starting Batch 2. Re-read Task N's failure-handling section.

---

## Batch 2: qbittorrent + sabnzbd (multi-PVC raw apps)

These apps have 2 PVCs each (config + gluetun-config). Both must migrate in lockstep — gluetun-config must be ready before the app pod starts (it's mounted into the gluetun sidecar which fronts the main container).

Each migration is its own PR, but each PR has 2 Restore CRs.

---

### Task 4: qbittorrent migration (2 PVCs)

**Files:**
- Create: `k3s/applications/qbittorrent/migration/restore.yaml` (containing 2 Restore CRs)
- Modify: `k3s/applications/qbittorrent/pvc.yaml:1-12` and `:21-28` (two PVC blocks)
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-qbittorrent.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `qbittorrent` in namespace `qbittorrent`, source PVCs `qbittorrent-config` (5Gi) + `gluetun-config` (1Gi)
- Produces: longhorn PVCs `qbittorrent-config` + `gluetun-config` bound and populated; snapshot policy using `longhorn-snapclass`

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/qbittorrent-longhorn -b feat/qbittorrent-longhorn origin/master
cd .worktrees/qbittorrent-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CRs (both PVCs in one file)**

Create `k3s/applications/qbittorrent/migration/restore.yaml` with TWO Restore CRs in the same file (separated by `---`):

```yaml
---
# Restore CR for the qbittorrent-config csi-hostpath-sc → longhorn migration.
# Operator-applied. Same pattern as prowlarr (this batch), headlamp #309.
# See prowlarr/migration/restore.yaml for the full header rationale.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: qbittorrent-config-longhorn-migration
  namespace: qbittorrent
spec:
  source:
    fromPolicy:
      name: qbittorrent
      offset: 0
  target:
    pvc:
      name: qbittorrent-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 5Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
    cache:
      capacity: 1Gi
      storageClassName: local-path
      mode: Ephemeral
  failurePolicy:
    backoffLimit: 2
    activeDeadlineSeconds: 1800
  policy:
    onMissingSnapshot: Fail
---
# Restore CR for the gluetun-config csi-hostpath-sc → longhorn migration.
# gluetun-config must be ready before qbittorrent deployment scales up —
# the gluetun sidecar's /gluetun mount must be valid or the init fails.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: gluetun-config-longhorn-migration
  namespace: qbittorrent
spec:
  source:
    fromPolicy:
      name: qbittorrent
      offset: 0
  target:
    pvc:
      name: gluetun-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 1Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/qbittorrent/migration/restore.yaml
git commit -m "feat(qbittorrent): add Restore CRs for qbittorrent-config + gluetun-config migration"
```

- [ ] **Step 3: Apply Restore CRs imperatively (both)**

```bash
kubectl scale deploy/qbittorrent -n qbittorrent --replicas=0
kubectl wait pod -l app=qbittorrent -n qbittorrent --for=delete --timeout=60s
kubectl get volumesnapshot -n qbittorrent -l kopiur.home-operations.com/policy-name=qbittorrent
# Clear stale VolumeSnapshots with pvc-as-source-protection finalizers if any
kubectl delete pvc -n qbittorrent qbittorrent-config
kubectl delete pvc -n qbittorrent gluetun-config
kubectl apply -f k3s/applications/qbittorrent/migration/restore.yaml
```

Watch both Restore CRs complete:
```bash
kubectl get restore -n qbittorrent -w
# Wait until both phases are Completed
```

Verify both PVCs:
```bash
kubectl get pvc -n qbittorrent -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
# Expected: both show storageClassName=longhorn, phase=Bound
```

- [ ] **Step 4: Write Commit 2 — pvc.yaml storageClassName changes (both PVCs)**

Edit `k3s/applications/qbittorrent/pvc.yaml`. Change BOTH `qbittorrent-config` and `gluetun-config` PVC blocks' `storageClassName` from `csi-hostpath-sc` to `longhorn`. Leave the `qbittorrent-media` PV/PVC block alone (it's smb-media, not csi-hostpath-sc).

After edit:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qbittorrent-config
  namespace: qbittorrent
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn   # was: csi-hostpath-sc
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gluetun-config
  namespace: qbittorrent
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn   # was: csi-hostpath-sc
  resources:
    requests:
      storage: 1Gi
---
# (smb-media PV/PVC blocks below — unchanged)
```

Stage and commit:
```bash
git add k3s/applications/qbittorrent/pvc.yaml
git commit -m "feat(qbittorrent): switch qbittorrent-config + gluetun-config storageClassName to longhorn"
```

Verify Flux reconciled and scale qbittorrent back:
```bash
kubectl get pvc -n qbittorrent -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
kubectl scale deploy/qbittorrent -n qbittorrent --replicas=1
kubectl wait pod -l app=qbittorrent -n qbittorrent --for=condition=Ready --timeout=180s
```

Verify both PVCs are mounted by the pod:
```bash
kubectl describe pod -l app=qbittorrent -n qbittorrent | grep -A 2 "Volumes:"
# Expected: qbittorrent-config and gluetun-config both listed
```

Verify VPN tunnel is up:
```bash
kubectl logs -l app=qbittorrent -n qbittorrent -c gluetun | tail -20
# Expected: VPN connection established lines
```

- [ ] **Step 5: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-qbittorrent.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-qbittorrent.yaml
git commit -m "feat(kopiur): switch qbittorrent snapshot policy to longhorn-snapclass"
```

- [ ] **Step 6: Cleanup follow-up**

Check `k3s/applications/qbittorrent/kustomization.yaml`:
```bash
grep -E "migration/" k3s/applications/qbittorrent/kustomization.yaml
```

If migration/ files are listed in resources, remove them. Commit fix if changed.

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/qbittorrent-longhorn
gh pr create --base master --head feat/qbittorrent-longhorn \
  --title "feat(qbittorrent): migrate qbittorrent-config + gluetun-config PVCs from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Multi-PVC migration in one PR (matches monitoring #311 pattern). See docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

```bash
kubectl get pvc -n qbittorrent
kubectl get pods -n qbittorrent -l app=qbittorrent
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/qbittorrent-longhorn
git branch -d feat/qbittorrent-longhorn
```

---

### Task 5: sabnzbd migration (2 PVCs)

**Files:**
- Create: `k3s/applications/sabnzbd/migration/restore.yaml` (containing 2 Restore CRs)
- Modify: `k3s/applications/sabnzbd/pvc.yaml` (two PVC blocks; skip the smb-media PV/PVC block)
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sabnzbd.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `sabnzbd` in namespace `sabnzbd`, source PVCs `sabnzbd-config` (5Gi) + `gluetun-config` (1Gi)
- Produces: longhorn PVCs `sabnzbd-config` + `gluetun-config` bound and populated; snapshot policy using `longhorn-snapclass`

**Special note:** sabnzbd-downloads is on local-path, NOT csi-hostpath-sc. Out of scope here. Leave it alone. Only `sabnzbd-config` and `gluetun-config` migrate.

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/sabnzbd-longhorn -b feat/sabnzbd-longhorn origin/master
cd .worktrees/sabnzbd-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CRs (both PVCs in one file)**

Create `k3s/applications/sabnzbd/migration/restore.yaml` with TWO Restore CRs:

```yaml
---
# Restore CR for the sabnzbd-config csi-hostpath-sc → longhorn migration.
# Operator-applied. Same pattern as qbittorrent (multi-PVC). See
# qbittorrent/migration/restore.yaml for the full header.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: sabnzbd-config-longhorn-migration
  namespace: sabnzbd
spec:
  source:
    fromPolicy:
      name: sabnzbd
      offset: 0
  target:
    pvc:
      name: sabnzbd-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 5Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
    cache:
      capacity: 1Gi
      storageClassName: local-path
      mode: Ephemeral
  failurePolicy:
    backoffLimit: 2
    activeDeadlineSeconds: 1800
  policy:
    onMissingSnapshot: Fail
---
# Restore CR for the gluetun-config csi-hostpath-sc → longhorn migration.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: sabnzbd-gluetun-config-longhorn-migration
  namespace: sabnzbd
spec:
  source:
    fromPolicy:
      name: sabnzbd
      offset: 0
  target:
    pvc:
      name: gluetun-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 1Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/sabnzbd/migration/restore.yaml
git commit -m "feat(sabnzbd): add Restore CRs for sabnzbd-config + gluetun-config migration"
```

- [ ] **Step 3: Apply Restore CRs imperatively (both)**

```bash
kubectl scale deploy/sabnzbd -n sabnzbd --replicas=0
kubectl wait pod -l app=sabnzbd -n sabnzbd --for=delete --timeout=60s
kubectl get volumesnapshot -n sabnzbd -l kopiur.home-operations.com/policy-name=sabnzbd
kubectl delete pvc -n sabnzbd sabnzbd-config
kubectl delete pvc -n sabnzbd gluetun-config
kubectl apply -f k3s/applications/sabnzbd/migration/restore.yaml
kubectl get restore -n sabnzbd -w
# Wait until both phases are Completed
kubectl get pvc -n sabnzbd -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
# Expected: sabnzbd-config and gluetun-config both show longhorn, Bound
```

- [ ] **Step 4: Write Commit 2 — pvc.yaml storageClassName changes (both PVCs)**

Edit `k3s/applications/sabnzbd/pvc.yaml`. Change BOTH `sabnzbd-config` and `gluetun-config` PVC blocks' `storageClassName` from `csi-hostpath-sc` to `longhorn`. Leave `sabnzbd-media` PV/PVC block alone (smb-media).

Stage and commit:
```bash
git add k3s/applications/sabnzbd/pvc.yaml
git commit -m "feat(sabnzbd): switch sabnzbd-config + gluetun-config storageClassName to longhorn"
```

Verify and scale sabnzbd back:
```bash
kubectl get pvc -n sabnzbd -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
kubectl scale deploy/sabnzbd -n sabnzbd --replicas=1
kubectl wait pod -l app=sabnzbd -n sabnzbd --for=condition=Ready --timeout=180s
kubectl logs -l app=sabnzbd -n sabnzbd -c gluetun | tail -20
# Expected: VPN connection established
```

- [ ] **Step 5: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sabnzbd.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sabnzbd.yaml
git commit -m "feat(kopiur): switch sabnzbd snapshot policy to longhorn-snapclass"
```

- [ ] **Step 6: Cleanup follow-up**

Check `k3s/applications/sabnzbd/kustomization.yaml`:
```bash
grep -E "migration/" k3s/applications/sabnzbd/kustomization.yaml
```

If migration/ files are listed in resources, remove them and commit fix.

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/sabnzbd-longhorn
gh pr create --base master --head feat/sabnzbd-longhorn \
  --title "feat(sabnzbd): migrate sabnzbd-config + gluetun-config PVCs from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Multi-PVC migration in one PR (matches monitoring #311 pattern). Note: sabnzbd-downloads is local-path and stays out of scope.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

```bash
kubectl get pvc -n sabnzbd
kubectl get pods -n sabnzbd -l app=sabnzbd
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/sabnzbd-longhorn
git branch -d feat/sabnzbd-longhorn
```

---

## Batch 2 verification gate

```bash
kubectl get pvc -n qbittorrent -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
kubectl get pvc -n sabnzbd -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
# Expected: config + gluetun-config both longhorn/Bound for each namespace; media PV/PVC stays smb-media
kubectl get pods -n qbittorrent -l app=qbittorrent
kubectl get pods -n sabnzbd -l app=sabnzbd
# Expected: both Running, VPN tunnel up (check gluetun logs)
```

If any migration fails, **stop** before starting Batch 3.

---

## Batch 3: tdarr (multi-PVC raw app + privileged mover)

Namespace `tdarr` already carries `kopiur.home-operations.com/privileged-movers: "true"` annotation (verified). The tdarr server image's entrypoint creates some root-owned files before user drop, which is why this namespace is privileged-mover enabled.

---

### Task 6: tdarr migration (2 PVCs)

**Files:**
- Create: `k3s/applications/tdarr/migration/restore.yaml` (containing 2 Restore CRs)
- Modify: `k3s/applications/tdarr/pvc.yaml:1-12` and `:20-32` (two PVC blocks)
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-tdarr-node-config.yaml:10`
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-tdarr-server-data.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `tdarr-node-config` (1Gi) + `tdarr-server-data` (10Gi) in namespace `tdarr`
- Produces: longhorn PVCs `tdarr-server-data` + `tdarr-node-config` bound and populated; both snapshot policies using `longhorn-snapclass`

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/tdarr-longhorn -b feat/tdarr-longhorn origin/master
cd .worktrees/tdarr-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CRs (both PVCs in one file)**

Create `k3s/applications/tdarr/migration/restore.yaml` with TWO Restore CRs:

```yaml
---
# Restore CR for the tdarr-server-data csi-hostpath-sc → longhorn migration.
# Operator-applied. tdarr namespace has privileged-movers annotation, so
# the snapshot policy's runAsUser=1027/runAsGroup=100 mover can also read
# root-owned files left by the tdarr-server entrypoint. The Restore inherits
# UID/GID from the snapshot, so restored files have correct ownership.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: tdarr-server-data-longhorn-migration
  namespace: tdarr
spec:
  source:
    fromPolicy:
      name: tdarr-server-data
      offset: 0
  target:
    pvc:
      name: tdarr-server-data
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 10Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
    cache:
      capacity: 1Gi
      storageClassName: local-path
      mode: Ephemeral
  failurePolicy:
    backoffLimit: 2
    activeDeadlineSeconds: 1800
  policy:
    onMissingSnapshot: Fail
---
# Restore CR for the tdarr-node-config csi-hostpath-sc → longhorn migration.
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: tdarr-node-config-longhorn-migration
  namespace: tdarr
spec:
  source:
    fromPolicy:
      name: tdarr-node-config
      offset: 0
  target:
    pvc:
      name: tdarr-node-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 1Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/tdarr/migration/restore.yaml
git commit -m "feat(tdarr): add Restore CRs for tdarr-server-data + tdarr-node-config migration"
```

- [ ] **Step 3: Apply Restore CRs imperatively (both)**

```bash
# Scale both deployments to 0
kubectl scale deploy/tdarr-server -n tdarr --replicas=0
kubectl scale deploy/tdarr-node -n tdarr --replicas=0
kubectl wait pod -l app=tdarr-server -n tdarr --for=delete --timeout=60s
kubectl wait pod -l app=tdarr-node -n tdarr --for=delete --timeout=60s

# Clear stale VolumeSnapshots if any
kubectl get volumesnapshot -n tdarr
# (filter on label if helpful)

# Delete old PVCs
kubectl delete pvc -n tdarr tdarr-server-data
kubectl delete pvc -n tdarr tdarr-node-config

# Apply
kubectl apply -f k3s/applications/tdarr/migration/restore.yaml

# Watch both Restore CRs
kubectl get restore -n tdarr -w
# Wait until both phases are Completed

# Verify
kubectl get pvc -n tdarr -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
# Expected: tdarr-server-data and tdarr-node-config both longhorn/Bound
```

- [ ] **Step 4: Write Commit 2 — pvc.yaml storageClassName changes (both PVCs)**

Edit `k3s/applications/tdarr/pvc.yaml`. Change BOTH `tdarr-server-data` and `tdarr-node-config` PVC blocks' `storageClassName` from `csi-hostpath-sc` to `longhorn`. Leave `tdarr-media` PV/PVC block alone (smb-media).

Stage and commit:
```bash
git add k3s/applications/tdarr/pvc.yaml
git commit -m "feat(tdarr): switch tdarr-server-data + tdarr-node-config storageClassName to longhorn"
```

Verify Flux reconciled and scale tdarr back:
```bash
kubectl get pvc -n tdarr -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
# Server first (it must be ready before node can register):
kubectl scale deploy/tdarr-server -n tdarr --replicas=1
kubectl wait pod -l app=tdarr-server -n tdarr --for=condition=Ready --timeout=180s
kubectl scale deploy/tdarr-node -n tdarr --replicas=1
kubectl wait pod -l app=tdarr-node -n tdarr --for=condition=Ready --timeout=180s
```

Verify both pods bound both PVCs:
```bash
kubectl describe pod -l app=tdarr-server -n tdarr | grep -A 5 "Volumes:"
kubectl describe pod -l app=tdarr-node -n tdarr | grep -A 5 "Volumes:"
```

- [ ] **Step 5: Write Commit 3 — both snapshot policies snapclass update**

Edit both `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-tdarr-server-data.yaml` AND `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-tdarr-node-config.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass` in each.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-tdarr-server-data.yaml k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-tdarr-node-config.yaml
git commit -m "feat(kopiur): switch tdarr-server-data + tdarr-node-config snapshot policies to longhorn-snapclass"
```

- [ ] **Step 6: Cleanup follow-up**

Check `k3s/applications/tdarr/kustomization.yaml`. Note: tdarr already has a `migration/` directory from the previous local-path → csi-hostpath-sc migration (files: `pvc-copy-stage1.yaml`, `pvc-copy-stage2.yaml`, `pvc-hostpath.yaml`). These are stale now but Flux is no longer applying them since they were never listed in resources.

```bash
grep -E "migration/" k3s/applications/tdarr/kustomization.yaml
```

If migration/ files are listed in resources, remove them and commit fix. Otherwise no-op.

Also clean up the stale migration files themselves (optional, see PR #312 precedent):
```bash
ls k3s/applications/tdarr/migration/
# If old stage1/stage2/hostpath PVCs exist, leave them in tree as record (matches gatus/headlamp/portainer pattern) — but ensure they're NOT in kustomization.yaml resources
```

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/tdarr-longhorn
gh pr create --base master --head feat/tdarr-longhorn \
  --title "feat(tdarr): migrate tdarr-server-data + tdarr-node-config PVCs from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Multi-PVC migration in one PR. Namespace already has privileged-movers annotation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

```bash
kubectl get pvc -n tdarr
kubectl get pods -n tdarr
# Expected: tdarr-server Running, tdarr-node Running, both PVCs longhorn/Bound
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/tdarr-longhorn
git branch -d feat/tdarr-longhorn
```

---

## Batch 3 verification gate

```bash
kubectl get pvc -n tdarr -o custom-columns=NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase
kubectl get pods -n tdarr
# Both server and node Running; both PVCs longhorn/Bound
```

---

## Batch 4: pihole + authentik (HelmRelease-managed apps)

These apps use HelmReleases. The storage class lives in chart values, so Commit 2 edits `helmrelease.yaml` instead of `pvc.yaml`. Suspending the HelmRelease before applying the Restore CR is critical.

---

### Task 7: pihole migration

**Files:**
- Create: `k3s/applications/pihole/migration/restore.yaml`
- Modify: `k3s/applications/pihole/helmrelease.yaml` (find `storageClass: "csi-hostpath-sc"` line)
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-pihole.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `pihole` in namespace `pihole`, source PVC `pihole` (1Gi)
- Produces: longhorn PVC `pihole` bound and populated; HelmRelease `persistence.storageClass: longhorn`; snapshot policy using `longhorn-snapclass`

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/pihole-longhorn -b feat/pihole-longhorn origin/master
cd .worktrees/pihole-longhorn
```

- [ ] **Step 2: Write Commit 1 — Restore CR**

Create `k3s/applications/pihole/migration/restore.yaml`. The snapshot policy uses privileged mover (runAsUser=0/runAsGroup=0) because pihole's chart-init creates `/etc/pihole/logrotate` as root before user drop. Namespace has privileged-movers annotation. Restore inherits from snapshot:

```yaml
---
# Restore CR for the pihole csi-hostpath-sc → longhorn migration.
# Operator-applied. Matches headlamp #309 pattern (HelmRelease-managed app).
# See headlamp/migration/restore.yaml for the full header rationale.
#
# pihole-specific notes:
# - Snapshot policy uses privileged mover (runAsUser=0) — namespace carries
#   kopiur.home-operations.com/privileged-movers: "true". The chart-init
#   creates /etc/pihole/logrotate as root before user drop, so the mover
#   must run as root to read it.
# - The Restore inherits UID/GID from the snapshot metadata. Restored files
#   are owned correctly for pihole-FTL.db / gravity.db which pihole opens
#   as pihole:pihole (UID/GID 999:999 in chart values).
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: pihole-longhorn-migration
  namespace: pihole
spec:
  source:
    fromPolicy:
      name: pihole
      offset: 0
  target:
    pvc:
      name: pihole
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 1Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/pihole/migration/restore.yaml
git commit -m "feat(pihole): add Restore CR for csi-hostpath-sc → longhorn migration"
```

- [ ] **Step 3: Apply Restore CR imperatively (with HelmRelease suspend)**

```bash
# Suspend the HelmRelease FIRST so the controller doesn't fight us:
kubectl patch helmrelease pihole -n pihole --type merge -p '{"spec":{"suspend":true}}'

# Scale deployment to 0 (releases RWO on old PVC)
kubectl scale deploy/pihole -n pihole --replicas=0
kubectl wait pod -l app=pihole -n pihole --for=delete --timeout=60s

# Clear stale VolumeSnapshots if any
kubectl get volumesnapshot -n pihole -l kopiur.home-operations.com/policy-name=pihole
# Patch out pvc-as-source-protection finalizers if any are stuck

# Delete the old PVC
kubectl delete pvc -n pihole pihole

# Apply the Restore CR
kubectl apply -f k3s/applications/pihole/migration/restore.yaml

# Watch
kubectl get restore -n pihole -w
# Wait for phase=Completed

# Verify
kubectl get pvc -n pihole pihole -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
```

- [ ] **Step 4: Write Commit 2 — helmrelease.yaml storageClass change**

Edit `k3s/applications/pihole/helmrelease.yaml`. Find the `storageClass: "csi-hostpath-sc"` line (the one inside the `persistence:` block, not any other storageClass reference). Change it to `storageClass: "longhorn"`.

Add a comment explaining the migration, mirroring the headlamp PR comment style:

```yaml
    persistence:
      enabled: true
      size: "1Gi"
      # -- Migrated from csi-hostpath-sc to longhorn in
      # feat/pihole-longhorn. The Restore CR in migration/restore.yaml
      # creates a new 'pihole' PVC on longhorn and populates it from
      # the latest kopia snapshot; the chart's PVC template then matches
      # what's already there and Helm doesn't recreate it.
      storageClass: "longhorn"
```

Stage and commit:
```bash
git add k3s/applications/pihole/helmrelease.yaml
git commit -m "feat(pihole): switch persistence storageClass to longhorn"
```

Un-suspend the HelmRelease so it reconciles:
```bash
kubectl patch helmrelease pihole -n pihole --type merge -p '{"spec":{"suspend":false}}'
```

Watch Flux reconcile:
```bash
kubectl get helmrelease -n pihole pihole -w
# Wait for Ready: True
```

Scale pihole back up:
```bash
kubectl scale deploy/pihole -n pihole --replicas=1
kubectl wait pod -l app=pihole -n pihole --for=condition=Ready --timeout=180s
```

Verify DNS works (the app's primary function):
```bash
# From any host, query a domain through pihole:
dig @192.168.1.201 example.com +short
# Expected: a public IP (e.g., 93.184.216.34)
```

Verify admin UI loads:
```bash
curl -sk https://pihole.homelab.properties/admin/ | head
```

- [ ] **Step 5: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-pihole.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-pihole.yaml
git commit -m "feat(kopiur): switch pihole snapshot policy to longhorn-snapclass"
```

- [ ] **Step 6: Cleanup follow-up**

Check `k3s/applications/pihole/kustomization.yaml` for stale migration/ entries. Commit fix if needed.

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/pihole-longhorn
gh pr create --base master --head feat/pihole-longhorn \
  --title "feat(pihole): migrate pihole PVC from csi-hostpath-sc to longhorn (preserve data)" \
  --body "HelmRelease-managed migration (matches headlamp #309, portainer #310/#312). Pihole namespace has privileged-movers annotation for the chart-init root-owned logrotate file.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 8: Wait for PR merge and Flux reconcile**

```bash
kubectl get pvc -n pihole pihole
kubectl get pods -n pihole -l app=pihole
dig @192.168.1.201 example.com +short
```

- [ ] **Step 9: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/pihole-longhorn
git branch -d feat/pihole-longhorn
```

---

### Task 8: authentik migration (HelmRelease + StatefulSet)

**Files:**
- Create: `k3s/applications/authentik/migration/restore.yaml`
- Modify: `k3s/applications/authentik/helmrelease.yaml` (find postgresql storageClass line)
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-authentik.yaml:10`

**Interfaces:**
- Consumes: snapshot policy `authentik` in namespace `authentik`, source PVC `data-authentik-postgresql-0` (2Gi, bitnami StatefulSet)
- Produces: longhorn PVC `data-authentik-postgresql-0` bound and populated; HelmRelease postgresql storageClass → longhorn; snapshot policy using `longhorn-snapclass`

**Critical:** The PVC name `data-authentik-postgresql-0` is fixed by the bitnami/postgresql StatefulSet's volumeClaimTemplate. The Restore CR's `target.pvc.name` MUST be exactly `data-authentik-postgresql-0` or the StatefulSet will not bind.

- [ ] **Step 1: Create worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/authentik-longhorn -b feat/authentik-longhorn origin/master
cd .worktrees/authentik-longhorn
```

- [ ] **Step 2: Locate authentik's chart storageClass settings**

```bash
grep -n "storageClass\|postgresql\|persistence" k3s/applications/authentik/helmrelease.yaml
```

Note the line(s) where `csi-hostpath-sc` is referenced. The authentik chart exposes postgresql as a sub-chart with its own persistence block. The bitnami/postgresql StatefulSet creates the PVC with name `<releasename>-postgresql-0` by default; with `auth: authentik`, that becomes `authentik-postgresql-0` — but the snapshot policy uses `data-authentik-postgresql-0` (note the `data-` prefix). Verify the actual PVC name in the cluster:

```bash
kubectl get pvc -n authentik
```

If the PVC name in the cluster is `data-authentik-postgresql-0`, the Restore CR uses that name. If it's different (e.g., the chart was renamed), adjust accordingly.

- [ ] **Step 3: Write Commit 1 — Restore CR**

Create `k3s/applications/authentik/migration/restore.yaml`:

```yaml
---
# Restore CR for the authentik-postgresql csi-hostpath-sc → longhorn migration.
# Operator-applied. Matches headlamp #309 pattern.
#
# authentik-specific notes:
# - Uses bitnami/postgresql StatefulSet. PVC name `data-authentik-postgresql-0`
#   is fixed by the volumeClaimTemplate (immutable). The Restore's
#   target.pvc.name MUST match exactly or the StatefulSet will fail to bind.
# - Bitnami postgres runs as UID/GID 1001. Namespace carries
#   kopiur.home-operations.com/privileged-movers: "true" so the snapshot
#   can read the few root-owned files the Bitnami chart-init creates before
#   user drop (same as pihole).
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: authentik-postgresql-longhorn-migration
  namespace: authentik
spec:
  source:
    fromPolicy:
      name: authentik
      offset: 0
  target:
    pvc:
      # MUST match StatefulSet volumeClaimTemplate name exactly
      name: data-authentik-postgresql-0
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 2Gi
  credentialProjection:
    enabled: true
  mover:
    inheritSecurityContextFrom:
      snapshot: {}
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

Stage and commit:
```bash
git add k3s/applications/authentik/migration/restore.yaml
git commit -m "feat(authentik): add Restore CR for csi-hostpath-sc → longhorn migration"
```

- [ ] **Step 4: Apply Restore CR imperatively (with HelmRelease suspend)**

```bash
# Suspend HelmRelease FIRST
kubectl patch helmrelease authentik -n authentik --type merge -p '{"spec":{"suspend":true}}'

# Scale postgresql StatefulSet to 0
kubectl scale statefulset/authentik-postgresql -n authentik --replicas=0
kubectl wait pod -l app.kubernetes.io/name=postgresql -n authentik --for=delete --timeout=120s

# Also scale the main authentik deployment so the app doesn't try to query DB
kubectl scale deploy/authentik -n authentik --replicas=0 2>/dev/null
kubectl scale deploy/authentik-worker -n authentik --replicas=0 2>/dev/null

# Clear stale VolumeSnapshots if any
kubectl get volumesnapshot -n authentik -l kopiur.home-operations.com/policy-name=authentik

# Delete the old PVC
kubectl delete pvc -n authentik data-authentik-postgresql-0

# Apply the Restore CR
kubectl apply -f k3s/applications/authentik/migration/restore.yaml

# Watch
kubectl get restore -n authentik -w
# Wait for phase=Completed

# Verify
kubectl get pvc -n authentik data-authentik-postgresql-0 -o jsonpath='{.spec.storageClassName}{"\t"}{.status.phase}{"\n"}'
# Expected: longhorn<TAB>Bound
```

- [ ] **Step 5: Write Commit 2 — helmrelease.yaml storageClass change**

Edit `k3s/applications/authentik/helmrelease.yaml`. Find the postgresql storageClass reference (likely `postgresql.primary.persistence.storageClass: csi-hostpath-sc` or similar). Change to `longhorn`.

Add a comment mirroring headlamp's pattern:
```yaml
    # Migrated from csi-hostpath-sc to longhorn in feat/authentik-longhorn.
    # The Restore CR in migration/restore.yaml creates a new
    # data-authentik-postgresql-0 PVC on longhorn and populates it from the
    # latest kopia snapshot; the StatefulSet's volumeClaimTemplate then
    # matches what's already there.
    storageClass: longhorn
```

Stage and commit:
```bash
git add k3s/applications/authentik/helmrelease.yaml
git commit -m "feat(authentik): switch postgresql storageClass to longhorn"
```

Un-suspend and reconcile:
```bash
kubectl patch helmrelease authentik -n authentik --type merge -p '{"spec":{"suspend":false}}'
kubectl get helmrelease -n authentik authentik -w
# Wait for Ready: True
```

Scale everything back up:
```bash
kubectl scale statefulset/authentik-postgresql -n authentik --replicas=1
kubectl wait pod -l app.kubernetes.io/name=postgresql -n authentik --for=condition=Ready --timeout=300s
kubectl scale deploy/authentik -n authentik --replicas=1
kubectl scale deploy/authentik-worker -n authentik --replicas=1
kubectl wait pod -l app.kubernetes.io/name=authentik -n authentik --for=condition=Ready --timeout=300s
```

Verify authentik works:
```bash
curl -sk https://authentik.homelab.properties/-/health/ready/
curl -sk https://authentik.homelab.properties/-/health/live/
# Both should return 200
```

Log in to authentik via WebUI and confirm users/groups intact.

- [ ] **Step 6: Write Commit 3 — snapshot policy snapclass update**

Edit `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-authentik.yaml`. Change `volumeSnapshotClassName: csi-hostpath-snapclass` to `longhorn-snapclass`.

Stage and commit:
```bash
git add k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-authentik.yaml
git commit -m "feat(kopiur): switch authentik snapshot policy to longhorn-snapclass"
```

- [ ] **Step 7: Cleanup follow-up — handle stale migration/ files**

authentik's `migration/` directory contains old artifacts from the local-path → csi-hostpath-sc migration (`postgresql-pvc-copy-stage1.yaml`, `postgresql-pvc-copy-stage2.yaml`, `postgresql-pvc-intermediate.yaml`).

```bash
ls k3s/applications/authentik/migration/
grep -E "migration/" k3s/applications/authentik/kustomization.yaml
```

If any migration/ files are listed in `kustomization.yaml` resources, remove them. The old PVCs themselves should be safe to leave in tree as record (matches gatus/headlamp/portainer pattern) but verify they don't conflict — if their storageClassName is csi-hostpath-sc, they will conflict with the new longhorn PVC.

Specifically: `postgresql-pvc-intermediate.yaml` likely declares a PVC with storageClassName: csi-hostpath-sc. If listed in kustomization resources, Flux will try to apply it and conflict with the StatefulSet-managed longhorn PVC. Remove from resources list (and consider removing the file entirely since the intermediate PVC no longer exists in cluster).

If cleanup changes are needed:
```bash
git add k3s/applications/authentik/kustomization.yaml
# Possibly: git rm k3s/applications/authentik/migration/postgresql-pvc-intermediate.yaml
git commit -m "fix(authentik): remove stale migration files from kustomization resources"
```

- [ ] **Step 8: Push and open PR**

```bash
git push -u origin feat/authentik-longhorn
gh pr create --base master --head feat/authentik-longhorn \
  --title "feat(authentik): migrate data-authentik-postgresql-0 PVC from csi-hostpath-sc to longhorn (preserve data)" \
  --body "Most complex migration: bitnami/postgresql StatefulSet with immutable volumeClaimTemplate. The Restore CR's target.pvc.name MUST be exactly data-authentik-postgresql-0.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 9: Wait for PR merge and Flux reconcile**

```bash
kubectl get pvc -n authentik
kubectl get pods -n authentik
curl -sk https://authentik.homelab.properties/-/health/ready/
```

- [ ] **Step 10: Clean up worktree**

```bash
cd /home/jeff/workspaces/homelab
git worktree remove .worktrees/authentik-longhorn
git branch -d feat/authentik-longhorn
```

---

## Task 9: Postflight — verify all migrations complete

**Why last:** Confirms the migration as a whole succeeded. If anything is still on csi-hostpath-sc that should be on longhorn, this task surfaces it.

- [ ] **Step 1: Confirm zero csi-hostpath-sc PVCs remain in target namespaces**

```bash
kubectl get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName,STATUS:.status.phase | grep csi-hostpath-sc
```

Expected output: empty. The only csi-hostpath-sc PVCs remaining should be the smb-media-related ones (none) or any PVCs that are intentionally NOT in scope (none for these 8 apps).

- [ ] **Step 2: Confirm all snapshot policies use longhorn-snapclass**

```bash
kubectl get snapshotpolicy -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SNAPCLASS:.spec.volumeSnapshotClassName | grep csi-hostpath-snapclass
```

Expected output: empty.

- [ ] **Step 3: Confirm all 8 apps are healthy**

For each app, run:
```bash
kubectl get pods -n <ns> -l app=<app>
# Expected: Running
```

Plus app-specific smoke tests:
- prowlarr: `curl -sk https://prowlarr.homelab.properties/ping`
- radarr: `curl -sk https://radarr.homelab.properties/ping`
- sonarr: `curl -sk https://sonarr.homelab.properties/ping`
- qbittorrent: `kubectl logs -n qbittorrent -l app=qbittorrent -c gluetun | grep "VPN is up"`
- sabnzbd: `kubectl logs -n sabnzbd -l app=sabnzbd -c gluetun | grep "VPN is up"`
- tdarr: WebUI loads, both server and node visible
- pihole: `dig @192.168.1.201 example.com +short`
- authentik: `curl -sk https://authentik.homelab.properties/-/health/ready/`

**Important:** pod-Running and ping/200 are NOT sufficient — sabnzbd-config passed both for ~90 minutes while running on a blank config (health probes don't check config content). Per Constraint 10 and the per-app content verification table, also confirm content identity:

- **prowlarr/radarr/sonarr:** log into WebUI, confirm indexers/apps/library lists are populated, not the fresh-install defaults.
- **qbittorrent:** WebUI loads, list of torrents visible (not empty if user had any), and `kubectl exec -n qbittorrent deploy/qbittorrent -c gluetun -- ls /gluetun` shows gluetun config files (or regenerated tunnel state from first start), NOT qBittorrent app files.
- **sabnzbd:** WebUI loads, indexers/categories/history visible (the smoking gun for the sabnzbd-config incident was an empty indexer list and ~15 `[section]` headers in `sabnzbd.ini` instead of the real ~25+).
- **authentik:** log in via WebUI, confirm users/groups intact (not the fresh-install admin-only state).
- **pihole:** query an external domain through pihole — the DNS-resolving part tests the data, the admin-UI-loading part doesn't.

- [ ] **Step 3a: sabnzbd `complete_dir` follow-up (Constraint H)**

Verify sabnzbd's WebUI Config → Folders → "Completed Download Folder" points at `/downloads/complete` (the dedicated `sabnzbd-downloads` PVC), NOT a path under `/config`. This is what caused the sabnzbd-config snapshot to be ~12.5GiB with media content, and *will recur on the next snapshot* if left unchanged. This check is in the human eyeball smoke test above — record the result in the migration completion doc.

If `complete_dir` is misconfigured, fix it via the WebUI (do not edit config files directly — sabnzbd overwrites them on shutdown). After fixing, take an immediate manual snapshot to verify the next policy-driven snapshot will be small:

```bash
kubectl create -f - <<EOF
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  name: sabnzbd-config-post-fix-oneshot
  namespace: sabnzbd
spec:
  policyName: sabnzbd-config
EOF
kubectl get snapshots -n sabnzbd sabnzbd-config-post-fix-oneshot -o jsonpath='{.status.stats.sizeBytes}{"\n"}'
# Expected: a few MB (config files only), not GB.
```

- [ ] **Step 4: Confirm next-hour snapshots succeed**

For each of the 8 apps, find the snapshot policy schedule and wait for the next hourly snapshot:

```bash
for ns in media pihole authentik qbittorrent sabnzbd tdarr; do
  echo "=== $ns ==="
  for policy in $(kubectl get snapshotpolicy -n "$ns" -o name | sed 's|.*/||'); do
    echo "  $policy:"
    kubectl get snapshots -n "$ns" --selector=kopiur.home-operations.com/config="$policy" --sort-by=.metadata.creationTimestamp | tail -2
  done
done
```

(prowlarr/radarr/sonarr all live in media; iterate their policies)

Expected: each app's most recent snapshot shows `status.phase: Succeeded` with a recent creation timestamp, using `longhorn-snapclass`.

- [ ] **Step 5: Document the migration**

Commit a summary doc:

```bash
cd /home/jeff/workspaces/homelab
git checkout master
git pull origin master
git checkout -b docs/migration-completion
mkdir -p docs/operations
cat > docs/operations/2026-08-20-csi-hostpath-longhorn-completion.md <<'EOF'
# csi-hostpath-sc → Longhorn migration completion

Date: 2026-08-20

All 11 csi-hostpath-sc PVCs across 8 apps migrated to Longhorn with no data loss:

- prowlarr (PR #<num>) — single PVC
- radarr (PR #<num>) — single PVC
- sonarr (PR #<num>) — single PVC
- qbittorrent (PR #<num>) — 2 PVCs (config + gluetun)
- sabnzbd (PR #<num>) — 2 PVCs (config + gluetun)
- tdarr (PR #<num>) — 2 PVCs (server-data + node-config)
- pihole (PR #<num>) — HelmRelease-managed
- authentik (PR #<num>) — HelmRelease + bitnami StatefulSet

Pattern: kopiur Restore CR + storageClassName change + snapshot policy snapclass update, per app, in 3 ordered commits.

Out of scope (deferred):
- 4 local-path PVCs (prometheus, loki, tempo, sabnzbd-downloads) — need separate migration to csi-hostpath-sc first
EOF
git add docs/operations/2026-08-20-csi-hostpath-longhorn-completion.md
git commit -m "docs(migration): record csi-hostpath-sc → longhorn migration completion"
git push -u origin docs/migration-completion
gh pr create --base master --head docs/migration-completion \
  --title "docs(migration): record csi-hostpath-sc → longhorn migration completion" \
  --body "Records the 8-PR migration completed in this session. See docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

After merge, clean up:
```bash
git checkout master
git pull origin master
git branch -d docs/migration-completion
```

---

## Failure handling (applies to any task)

### Restore CR stalls in `Pending` with `MissingCredentialsSecret`

Cause: `credentialProjection.enabled: true` is missing or the ClusterRepository secret lookup is wrong.

Fix:
1. Delete the Restore CR: `kubectl delete restore -n <ns> <name>`
2. Verify ClusterRepository `nas` is healthy: `kubectl get clusterrepository nas -o yaml`
3. Verify the source snapshot policy's `credentialProjection.enabled: true`
4. Re-apply the Restore CR with the field set correctly

### Restore CR fails with `snapshot not found`

Cause: snapshot policy's `policy.onMissingSnapshot` is `Fail` (correct setting) but no snapshot exists.

Fix:
1. Delete the Restore CR
2. Trigger a one-off snapshot: `kubectl create -f - <<EOF\napiVersion: kopiur.home-operations.com/v1alpha1\nkind: Snapshot\nmetadata:\n  name: <name>-oneshot\n  namespace: <ns>\nspec:\n  policyName: <policy>\nEOF`
3. Wait for snapshot to succeed
4. Re-apply the Restore CR

### Commit 2 causes Flux conflict / HelmRelease stuck

Cause: per portainer #312, usually means `migration/` files listed in `kustomization.yaml` resources conflict with the HelmRelease-managed PVC.

Fix:
1. Don't panic. The PVC is already restored (Commit 1 succeeded). The chart-managed PVC just can't bind.
2. Remove `migration/` entries from `k3s/applications/<app>/kustomization.yaml`
3. Flux re-reconciles; chart's PVC template now matches the existing longhorn PVC
4. Verify: `kubectl get pvc -n <ns> <pvc>`

### Pod won't start on longhorn PVC (UID/GID mismatch)

Symptom: Pod CrashLoopBackOff with "Permission denied" errors reading files in the mounted PVC.

Fix:
1. Exec into a debug pod with the longhorn PVC mounted: `kubectl debug -n <ns> -it --image=busybox --target=<container>`
2. Inspect file ownership: `ls -la /<mount-path>`
3. Compare to what the chart expects (e.g., UID 999 for pihole, UID 1027 for LinuxServer apps)
4. If ownership is wrong, the snapshot policy recorded wrong UID/GID. Either:
   - Adjust `mover.securityContext.runAsUser/runAsGroup` in the Restore CR to match what the chart wants, re-apply
   - Or run a chown job manually after restore: `kubectl create job -n <ns> chown-fix --image=busybox -- chown -R <uid>:<gid> /<mount-path>`

### Restore fails mid-mover (data partially restored)

Cause: mover Job crashed (network, kopia repository corruption, mover bug).

Fix:
1. Delete the Restore CR: `kubectl delete restore -n <ns> <name>`
2. Delete the partial longhorn PVC: `kubectl delete pvc -n <ns> <pvc>`
3. Investigate mover Job logs: `kubectl logs -n <ns> -l job-name=kopiur-mover-<restore-name>`
4. Fix root cause
5. Re-apply the Restore CR (idempotent — creates a fresh PVC and re-runs the mover)

### Flux dry-run stuck on `storageClassName` mismatch (portainer #310/#312)

Symptom: after Commit 2, `flux logs` or `flux reconcile kustomization apps` shows the chart wants to change `storageClassName` from `longhorn` back to `csi-hostpath-sc`, despite the in-tree value being `longhorn`. HelmRelease never reaches `Ready: True`.

CRITICAL: do **NOT** `kubectl delete helmrelease`, `kubectl delete pvc`, or `kubectl delete deployment` to "fix" this. Helm-controller GC will garbage-collect the chart-managed PVC and permanently destroy the restored data (portainer #310 incident).

**First step — grep the repo for the conflict (portainer #312 lesson):**

```bash
grep -rn "csi-hostpath-sc" k3s/applications/<app>/
# Most likely cause: a stale migration/ file listed in kustomization.yaml resources
grep -E "migration/" k3s/applications/<app>/kustomization.yaml
```

If a stale `migration/*.yaml` is listed in resources, the fix is to remove it from the resources list (separate fix PR; do not bundle with the migration PR). After the fix lands, Flux's dry-run will see the in-tree value as the source of truth.

**If the repo is clean** — restart controllers in this order (each is a pod delete, not a resource delete):

1. `flux reconcile kustomization apps --with-source`
2. `kubectl delete pod -n flux-system -l app=helm-controller`
3. `kubectl delete pod -n flux-system -l app=kustomize-controller`
4. Wait for the next reconcile interval

If still stuck after all four, the issue is not a cache — escalate, do not delete resources.

### Stale Completed pods holding `pvc-protection` finalizers (memory: `csi-hostpath-to-longhorn-restore-cr`)

Symptom: source PVC won't delete (`kubectl delete pvc` hangs), or the new longhorn PVC won't bind (`describe pvc` shows `Used By:` listing a Completed pod).

Cause: Completed migration pods from previous migrations (e.g., the rsync jobs from PR #298) hold `kubernetes.io/pvc-protection` finalizers on the source PVC.

Fix:
```bash
# List Completed pods in the namespace:
kubectl get pods -n <ns> -o jsonpath='{.items[?(@.status.phase=="Succeeded")].metadata.name}{"\n"}'
# Delete the stale ones (NOT the deployment, NOT the new Restore CR's mover pod):
kubectl delete pod -n <ns> <stale-completed-pod>
```
If a mover pod itself is stuck (still Running but finalizer not released), check `kubectl describe pvc -n <ns> <pvc> -o jsonpath='{.metadata.finalizers}'` and `kubectl get pods -n <ns> -o yaml | grep -A 5 pvc-protection` to find the holder.

### Reverse-recovery after discovering the app is on a blank PVC

If post-migration verification reveals the app is running on a freshly-reprovisioned empty PVC (the sabnzbd-config incident): the recovery is **not** another Restore CR using `fromPolicy` (the policy's latest snapshot is now of the blank state and will silently restore nothing useful). Use `spec.source.snapshotRef` pinned to a pre-incident `Discovered` Snapshot CR.

```bash
# 1. Find the last known-good pre-incident Snapshot CR
kubectl get snapshots -n <ns> -l kopiur.home-operations.com/config=<policy> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.endTime}{"\t"}{.status.stats.sizeBytes}{"\n"}' \
  | sort -k2
# Pick the snapshot with realistic sizeBytes (the one taken before the blank state)

# 2. Create a recovery Restore CR mirroring the existing migration/restore.yaml
#    but with source.snapshotRef instead of source.fromPolicy:
#    spec:
#      source:
#        snapshotRef:
#          name: nas-disc-37aa4b30bc50cd5f  # the last pre-incident snapshot
#          namespace: <ns>

# 3. Scale app to 0, delete blank PVC, apply recovery Restore CR
# 4. Verify content (per-app content verification table above)
# 5. Scale back up
```

Worked example for sabnzbd-config: `docs/superpowers/plans/2026-08-21-restore-sabnzbd-config-from-kopia-backup.md`. The same procedure applies to any PVC discovered on a fresh blank state after a failed or abandoned migration.

---

## Self-review (run after writing the plan)

1. **Spec coverage:** Each of the 8 apps in the spec has a dedicated task (Tasks 1-8). The preflight (Task 0) and postflight (Task 9) cover backup health verification before/after. Each task implements the 3-commit pattern from the spec.

2. **Placeholder scan:** All Restore CRs have full content (no "TBD"/"TODO"). All commits have explicit step content.

3. **Type consistency:** Restore CR structure is identical across all tasks (only `name`, `namespace`, `policy name`, `pvc name`, `capacity` differ). Snapshot policy field names (`volumeSnapshotClassName`) match. PVC field names (`storageClassName`) match.

4. **Ambiguity check:** Authentik's StatefulSet PVC name is explicitly called out as critical (`data-authentik-postgresql-0` must match exactly). Multi-PVC apps have explicit lockstep language (both PVCs in one file, both must be ready). HelmRelease apps have explicit `suspend:true` / `suspend:false` lifecycle.

5. **Failure paths:** Dedicated section covers all known failure modes (stalls, missing snapshots, Flux conflicts, UID/GID mismatch, partial restore).

6. **Cleanup follow-ups:** Each raw-app task has a Step 6 that checks `kustomization.yaml` resources. Authentik has an explicit cleanup step for stale migration/ files (which is known to be a problem per the `conflicting PVC definitions` finding).
