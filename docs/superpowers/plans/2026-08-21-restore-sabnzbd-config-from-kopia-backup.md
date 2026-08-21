# Restore sabnzbd-config from Kopia Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover sabnzbd's real `/config` data (indexers, categories, history, API key, RSS feeds) which was lost when Task 5 of the csi-hostpath→longhorn migration deleted the source PVC and its Restore CR failed, leaving sabnzbd running on a blank auto-provisioned PVC for the last ~1.5 hours.

**Architecture:** Restore directly from the specific pre-incident kopiur Snapshot CR (`nas-disc-37aa4b30bc50cd5f`, 2026-08-21T20:06:31Z, 13,440,175,543 bytes) into a fresh `longhorn` PVC named `sabnzbd-config`, using `spec.source.snapshotRef` (NOT `fromPolicy` — the policy's current latest snapshot is of the *already-blank* state and would silently restore nothing useful). The snapshot is oversized (~12.5GiB) because sabnzbd's own `complete_dir` setting historically wrote into `/config/Downloads/complete` instead of the dedicated `/downloads` PVC — this is why the original migration plan (Task 5) deferred `sabnzbd-config` in the first place (see `k3s/applications/sabnzbd/migration/restore.yaml` header comment). We restore everything as-is to guarantee no data loss, then clean up the misplaced media and fix the setting so it can't recur.

**Tech Stack:** k3s, Flux v2, Kustomize, kopiur (Restore/Snapshot CRDs), Longhorn CSI (`numberOfReplicas: 1`, single-node, 225Gi free).

**Spec:** `docs/superpowers/specs/2026-08-20-finish-csi-hostpath-to-longhorn-migration-design.md` (this plan is a corrective follow-up to that spec's Task 5, which is what left `sabnzbd-config` unmigrated and then got its source PVC deleted before the follow-up restore was ever created).

## Global Constraints

1. **No further data loss.** Do not delete the current blank `sabnzbd-config` PVC until the Restore CR against `nas-disc-37aa4b30bc50cd5f` has been created and its manifest reviewed — there is no undo once that PVC is gone.
2. **Restore CR is operator-applied (`kubectl apply -f`), never listed in `kustomization.yaml`** — Flux would refight it every reconcile (established repo pattern, see qbittorrent/gluetun migrations).
3. **`pvc.yaml` is Flux-managed** (listed in `k3s/applications/sabnzbd/kustomization.yaml`). Its `storageClassName`/`resources.requests.storage` are immutable on a bound PVC — push the git change only *after* the Restore CR has already created the PVC with matching spec, or Flux's dry-run will fail loudly (as already observed once in the cluster events during this incident) until it converges.
4. **Target snapshot is pinned by name (`snapshotRef`), not `fromPolicy`.** The `sabnzbd-config` SnapshotPolicy's own schedule has already taken snapshots of the *post-wipe* blank state (e.g. `sabnzbd-config-scheduled-20260821221600`, 44579 bytes) — using `fromPolicy` here would restore garbage.
5. **All git changes happen on a feature branch**, PR'd like the other migration work (#317/#318/#321). No commits to `master` directly.

## Current State (verified live, 2026-08-21 ~22:50 UTC)

- `sabnzbd-config` PVC: `csi-hostpath-sc`, 5Gi, created `2026-08-21T21:41:35Z`, Bound, contains only a freshly-generated default `sabnzbd.ini` (148K total) — this is the blank state to be replaced.
- `gluetun-config` PVC: already on `longhorn`, 1Gi, correctly restored (Task 5 partial completion) — do not touch.
- Target snapshot `nas-disc-37aa4b30bc50cd5f` (namespace `sabnzbd`): `phase: Discovered`, `deletionPolicy: Retain`, `hostname: sabnzbd`, `sourcePath: /config`, `kopiaSnapshotID: 37aa4b30bc50cd5fb668199cb75cc5ef`, `sizeBytes: 13440175543`, `endTime: 2026-08-21T20:06:31Z` — still present, confirmed via `kubectl get`.
- No `sabnzbd-config-*` Restore CR exists yet in the `sabnzbd` namespace (only `sabnzbd-gluetun-config-longhorn-migration`, Completed).
- Longhorn: `numberOfReplicas: 1`, node `homelab` has 225Gi available — ample room for a ~20Gi target PVC.
- `snapshotpolicy-sabnzbd-config.yaml` still points at `csi-hostpath-snapclass` (needs updating to `longhorn-snapclass` alongside the PVC storage class change, matching the pattern already applied for gluetun).

---

### Task 1: Pre-flight re-verification

**Files:** none (read-only)

- [ ] **Step 1: Re-confirm the target snapshot hasn't been pruned and the blank PVC hasn't changed**

```bash
kubectl get snapshots.kopiur.home-operations.com -n sabnzbd nas-disc-37aa4b30bc50cd5f -o jsonpath='{.status.phase} {.status.stats.sizeBytes} {.spec.deletionPolicy}{"\n"}'
kubectl get pvc sabnzbd-config -n sabnzbd -o jsonpath='{.spec.storageClassName} {.metadata.creationTimestamp}{"\n"}'
```

Expected: `Discovered 13440175543 Retain` and `csi-hostpath-sc 2026-08-21T21:41:35Z`. If either has changed (snapshot gone, or PVC age/class different — meaning someone else already acted), STOP and re-diagnose before continuing.

- [ ] **Step 2: Confirm no in-flight Restore CR already targets sabnzbd-config**

```bash
kubectl get restores.kopiur.home-operations.com -n sabnzbd
```

Expected: only `sabnzbd-gluetun-config-longhorn-migration` (Completed). If a `sabnzbd-config-*` Restore already exists, stop and inspect it instead of creating a duplicate.

---

### Task 2: Create the worktree and the Restore CR manifest

**Files:**
- Create: `.worktrees/sabnzbd-config-recovery` (git worktree, branch `fix/sabnzbd-config-recovery`)
- Create: `k3s/applications/sabnzbd/migration/restore-config.yaml`

**Interfaces:**
- Produces: a `Restore` CR named `sabnzbd-config-longhorn-migration` in namespace `sabnzbd`, targeting a new PVC `sabnzbd-config` (`longhorn`, `20Gi`, RWO).

- [ ] **Step 1: Create the worktree**

```bash
cd /home/jeff/workspaces/homelab
git fetch origin master
git worktree add .worktrees/sabnzbd-config-recovery -b fix/sabnzbd-config-recovery origin/master
cd .worktrees/sabnzbd-config-recovery
```

- [ ] **Step 2: Write the Restore CR**

Create `k3s/applications/sabnzbd/migration/restore-config.yaml`:

```yaml
---
# Recovery Restore CR for sabnzbd-config, pinned to the last known-good
# pre-incident snapshot.
#
# Context: Task 5 of the csi-hostpath->longhorn migration deleted the
# source sabnzbd-config PVC and its Restore CR failed (multi-source
# SnapshotPolicy bug, fixed in PR #318) and was never retried. sabnzbd's
# manifest then dynamically provisioned a brand-new empty PVC and the app
# has been running as a blank install since 2026-08-21T21:41:35Z.
#
# This restores from `nas-disc-37aa4b30bc50cd5f`, a Discovered Snapshot CR
# (deletionPolicy: Retain) recorded 2026-08-21T20:06:31Z, ~90 minutes
# before the wipe — the newest snapshot known to hold real config data.
# Pinned explicitly via snapshotRef, NOT fromPolicy: the SnapshotPolicy's
# own scheduled snapshots since the wipe are of the blank state and would
# silently restore nothing useful.
#
# Target capacity is 20Gi (not the original plan's 5Gi) because this
# snapshot is ~12.5GiB — sabnzbd's complete_dir setting has historically
# written completed downloads into /config/Downloads/complete instead of
# the dedicated /downloads PVC, so the config snapshot carries that media
# along with it. See Task 4 in this plan for the cleanup/fix.
#
# Operator-applied (NOT in kustomization.yaml — Flux will not reconcile it
# on every sync). Run with `kubectl apply -f` once after scaling sabnzbd
# to 0 replicas and deleting the current blank sabnzbd-config PVC.
#
# Pre-conditions:
#   - sabnzbd deployment scaled to 0
#   - The blank csi-hostpath-sc PVC `sabnzbd-config` deleted (Restore's
#     target.pvc would otherwise hit a name conflict)
#
# Post-conditions:
#   - PVC `sabnzbd-config` exists, bound on `longhorn`, populated with the
#     real pre-incident config (sabnzbd.ini, admin/, logs/, Downloads/).
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: sabnzbd-config-longhorn-migration
  namespace: sabnzbd
spec:
  source:
    snapshotRef:
      name: nas-disc-37aa4b30bc50cd5f
      namespace: sabnzbd
  target:
    pvc:
      name: sabnzbd-config
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      capacity: 20Gi
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
    activeDeadlineSeconds: 3600
```

- [ ] **Step 3: Commit**

```bash
git add k3s/applications/sabnzbd/migration/restore-config.yaml
git commit -m "fix(sabnzbd): add recovery Restore CR for lost sabnzbd-config"
```

---

### Task 3: Execute the restore against the live cluster

**Files:** none (imperative cluster operations)

- [ ] **Step 1: Scale sabnzbd to 0**

```bash
kubectl scale deployment sabnzbd -n sabnzbd --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=sabnzbd -n sabnzbd --timeout=60s || kubectl get pods -n sabnzbd
```

Expected: no `sabnzbd-*` app pod remains (gluetun/exportarr sidecars are in the same pod, so they go too).

- [ ] **Step 2: Delete the blank sabnzbd-config PVC**

```bash
kubectl delete pvc sabnzbd-config -n sabnzbd
```

Expected: PVC deletes cleanly (nothing else mounts it once the deployment is scaled to 0).

- [ ] **Step 3: Apply the Restore CR**

```bash
kubectl apply -f k3s/applications/sabnzbd/migration/restore-config.yaml
```

- [ ] **Step 4: Watch it to completion**

```bash
kubectl get restore sabnzbd-config-longhorn-migration -n sabnzbd -w
```

Expected: phase progresses `Pending` → `Resolving` → `Restoring` → `Completed`. Given ~12.5GiB of data, expect several minutes (gluetun's 1GiB restore took 31s; budget up to the 3600s `activeDeadlineSeconds` but it should finish well before that). If phase goes to a failure state, run `kubectl describe restore sabnzbd-config-longhorn-migration -n sabnzbd` and stop — do not retry blindly (systematic-debugging: find root cause before re-attempting).

- [ ] **Step 5: Verify the restored PVC and data**

```bash
kubectl get pvc sabnzbd-config -n sabnzbd -o jsonpath='{.spec.storageClassName} {.status.capacity.storage} {.status.phase}{"\n"}'
kubectl run sabnzbd-config-check --rm -i --restart=Never -n sabnzbd --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"check","image":"busybox:1.36","command":["sh","-c","ls -la /config && echo --- && grep -c '\''^\['\'' /config/sabnzbd.ini && du -sh /config/Downloads/complete 2>/dev/null"],"volumeMounts":[{"name":"cfg","mountPath":"/config"}]}],"volumes":[{"name":"cfg","persistentVolumeClaim":{"claimName":"sabnzbd-config"}}]}}'
```

Expected: `longhorn 20Gi Bound`; `sabnzbd.ini` present with a real section count (a fresh-install ini has ~15-20 `[...]` sections but near-empty values — cross-check against the file size, ~7-8KB observed pre-wipe vs the current 44KB+ real one should look substantially different/larger with actual indexer/category entries); `admin/` directory present (contains the history database). This is the actual correctness check — don't just trust `Completed` phase.

- [ ] **Step 6: Scale sabnzbd back to 1**

```bash
kubectl scale deployment sabnzbd -n sabnzbd --replicas=1
kubectl rollout status deployment sabnzbd -n sabnzbd --timeout=120s
```

- [ ] **Step 7: Verify the app itself**

```bash
kubectl exec -n sabnzbd deploy/sabnzbd -c sabnzbd -- wget -qO- -T5 http://localhost:8080/api?mode=version 2>&1
```

Confirm the WebUI/API responds, then have the user (jander99) log into the WebUI and eyeball that indexers/categories/history are back — this is the one verification step that requires a human, not a command.

---

### Task 4: Land the GitOps changes (PR)

**Files:**
- Modify: `k3s/applications/sabnzbd/pvc.yaml` (`sabnzbd-config` block: `storageClassName: longhorn`, `storage: 20Gi`)
- Modify: `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sabnzbd-config.yaml:11` (`volumeSnapshotClassName: longhorn-snapclass`)
- Modify: `k3s/applications/sabnzbd/kustomization.yaml` (remove `migration/restore-config.yaml` reference if it was ever added — it should NOT be there per Global Constraint #2; this step is a safety check, not an expected change)

**Interfaces:**
- Consumes: the already-restored, already-verified `sabnzbd-config` PVC from Task 3 (must not push this commit before Task 3 Step 5 passes, or Flux will hit the immutable-field dry-run error seen earlier in this incident).

- [ ] **Step 1: Update pvc.yaml**

Edit the `sabnzbd-config` block in `k3s/applications/sabnzbd/pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sabnzbd-config
  namespace: sabnzbd
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn   # was: csi-hostpath-sc
  resources:
    requests:
      storage: 20Gi   # was: 5Gi — snapshot data includes misplaced Downloads/complete, see Task 5
```

- [ ] **Step 2: Update the snapshot policy snapclass**

In `k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sabnzbd-config.yaml`, change:

```yaml
  volumeSnapshotClassName: longhorn-snapclass   # was: csi-hostpath-snapclass
```

- [ ] **Step 3: Verify Flux will reconcile cleanly (dry-run)**

```bash
flux build kustomization apps --path k3s/applications --dry-run 2>&1 | grep -A5 sabnzbd-config
```

Expected: no diff beyond what was just edited, no immutable-field errors (the live PVC already matches this spec from Task 3).

- [ ] **Step 4: Commit and push**

```bash
git add k3s/applications/sabnzbd/pvc.yaml k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-sabnzbd-config.yaml
git commit -m "fix(sabnzbd): migrate sabnzbd-config to longhorn, sync snapshot policy"
git push -u origin fix/sabnzbd-config-recovery
```

- [ ] **Step 5: Open PR**

```bash
gh pr create --title "fix(sabnzbd): recover sabnzbd-config from kopia backup, complete longhorn migration" --body "$(cat <<'EOF'
## Summary
- Restores sabnzbd-config data lost when Task 5 of the csi-hostpath->longhorn
  migration deleted the source PVC before its Restore CR ever succeeded
  (multi-source SnapshotPolicy bug, fixed in #318, but the retry never happened)
- Restore CR pinned explicitly to the last known-good pre-incident snapshot
  (nas-disc-37aa4b30bc50cd5f, 2026-08-21T20:06:31Z) via snapshotRef, since the
  policy's own post-incident scheduled snapshots are of the blank state
- Completes the deferred half of #321/#320's sabnzbd migration: sabnzbd-config
  now on longhorn (20Gi, sized for the misplaced Downloads/complete data
  currently embedded in /config — see follow-up cleanup task)

## Test plan
- [x] Restore CR completed, PVC verified bound on longhorn with real config content
- [x] sabnzbd WebUI/API responds post-restore
- [ ] User confirms indexers/categories/history visible in WebUI
EOF
)"
```

---

### Task 5: Follow-up — stop future config snapshots from including download data

**Files:** none yet — this is a decision point for the user, not an autonomous change.

**Context:** the restored `/config/Downloads/complete` directory holds real media files that don't belong under `/config` — this is why the snapshot was ~12.5GiB and why the original Task 5 plan deferred this restore. Two independent things need deciding, not doing:

- [ ] **Step 1: Confirm with the user before moving anything**

Ask jander99 whether `/config/Downloads/complete` should be (a) moved into the existing `sabnzbd-downloads` PVC (`/downloads`, already mounted, 200Gi on local-path) or (b) deleted outright if those completed downloads are stale/already processed by *arr apps. Do not decide or execute this unilaterally — it's real user media data.

- [ ] **Step 2: Fix sabnzbd's own `complete_dir` setting**

Once the WebUI is confirmed working (Task 3 Step 7), have the user (or do it with explicit go-ahead) check Config → Folders → "Completed Download Folder" in the sabnzbd WebUI and point it at `/downloads/complete` instead of a path resolving under `/config`. This is what caused the contamination originally and will recur on the next scheduled snapshot if left unchanged.

---

## Self-Review

- **Spec coverage:** Restores the exact PVC/data the original Task 5 deferred (`sabnzbd-config`); completes the storageClassName + snapclass changes the "bundled changes" pattern requires; does not touch `gluetun-config` (already correct) or `sabnzbd-downloads` (out of scope, confirmed in original plan doc).
- **No placeholders:** every kubectl/yaml step above is a real, complete command or manifest — nothing deferred to "add error handling" style hand-waving.
- **Destructive-step callout:** Task 3 Step 2 (`kubectl delete pvc sabnzbd-config`) is the only irreversible action in this plan, and it's gated behind Task 1's re-verification and happens only after the replacement Restore CR manifest is already written and reviewed (Task 2). Get explicit go-ahead before running Task 3.
