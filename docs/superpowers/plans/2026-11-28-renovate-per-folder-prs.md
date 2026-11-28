# Renovate Per-Folder PRs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Renovate opens one PR per k3s folder name, so one service can be reverted alone.

**Architecture:** A single templated `packageRules` entry in `renovate.json` replaces the four k3s groups. A later k3s rule undoes the template so the version pin stays in one PR.

**Tech Stack:** Renovate 40.5.0 (version pinned in `.github/workflows/renovate-validate.yaml`), `npx`.

**Spec:** `docs/superpowers/specs/2026-11-28-renovate-per-folder-prs-design.md`

## Global Constraints

- Work in `/home/jeff/workspaces/homelab-renovate-per-folder`, branch `chore/renovate-per-folder`.
- No automerge. Docker stays ignored. Ansible, npm and GitHub Actions rules are unchanged.
- `prHourlyLimit` stays 5; schedule stays `before 6am on Monday`.
- Open a PR; never merge it.

## Review Focus

- `plan.yaml` is inside the templated path: k3s must still produce one branch for both files (Task 1 test).
- Major updates must stay on a separate, recognisable branch and title (Task 1 test).
- Same-named folders (`monitoring`, `authentik`) must share one branch (Task 1 test).
- Ansible, npm and GitHub Actions branches must keep their current names (Task 1 test).
- `ignorePaths` must not hide anything outside `migration/` folders (Task 1 test).

---

### Task 1: Per-folder grouping in `renovate.json`

**Files:**
- Modify: `renovate.json`

- [ ] **Step 1: Build a test copy with stale pins**

`git clone` the worktree into a new `mktemp -d` directory under the session scratchpad. In the clone only, lower these pins to an older real version:
- one image in `k3s/applications/sonarr/` and one in `k3s/applications/radarr/` (minor or patch)
- the Loki chart in `k3s/infrastructure/controllers/loki/helmrelease.yaml` (previous major)
- one pin each in `k3s/applications/monitoring/` and `k3s/infrastructure/configs/monitoring/`
- the k3s version in both `plan.yaml` and `group_vars/all.yml`
- one collection in the Ansible requirements file

- [ ] **Step 2: Run the lookup and confirm the old grouping**

In the clone (set `GITHUB_COM_TOKEN="$(gh auth token)"` in the environment, never echo it):

```bash
LOG_FILE=../before.log LOG_FILE_LEVEL=debug npx --yes --package renovate@40.5.0 -- renovate --platform=local
grep -oE '"branchName": ?"[^"]+"' ../before.log | sort -u
```

Expected: `renovate/flux-infra-controllers` or `renovate/major-flux-infra-controllers`, and `renovate/kubernetes-images`; no `sonarr` branch. If the log holds no `branchName` entries, stop and report: this test method needs replacing.

- [ ] **Step 3: Edit `renovate.json`**

Replace the four rules grouping `flux-infra-controllers`, `flux-infra-configs`, `flux-applications` and `kubernetes-images` with:

```json
{
  "description": "One branch per k3s folder name so a service can be merged and reverted alone",
  "matchFileNames": ["k3s/applications/**", "k3s/infrastructure/**"],
  "groupName": "k3s-workloads",
  "additionalBranchPrefix": "{{parentDir}}-",
  "semanticCommitScope": "{{parentDir}}"
}
```

Move the `k3s-io/k3s` rule after it and add `"additionalBranchPrefix": ""` and `"semanticCommitScope": "deps"` (later rules win). Add `"**/migration/**"` to `ignorePaths`. Set `"prConcurrentLimit": 25`.

- [ ] **Step 4: Validate**

Run: `npx --yes --package renovate@40.5.0 -- renovate-config-validator renovate.json`
Expected: `Config validated successfully`

- [ ] **Step 5: Re-run the lookup**

Copy the new `renovate.json` into the clone, repeat Step 2 with `../after.log`.

Expected:
- `renovate/sonarr-k3s-workloads` and `renovate/radarr-k3s-workloads`
- a Loki branch matching `renovate/loki-(major-)?k3s-workloads|renovate/major-loki-k3s-workloads`, with `major` in it
- exactly one `monitoring` branch per update type
- exactly one k3s branch, `renovate/k3s`, covering both files
- the Ansible branch name identical to `before.log`; npm and GitHub Actions likewise if present
- no branch containing `migration`, and no package file under `migration/`
- package file list otherwise identical to `before.log`
- PR titles scoped by folder (`chore(sonarr): …`), the Loki title still identifiable as major, the k3s title `chore(deps): …`

If a title or branch differs, fix the rule and repeat Steps 4 and 5.

- [ ] **Step 6: Commit**

```bash
git add renovate.json
git commit -m "chore(renovate): split k3s updates into one PR per folder"
```

### Task 2: Open the PR

- [ ] **Step 1:** Run `git fetch origin master` and rebase if behind.
- [ ] **Step 2:** Push the branch and open a PR against `master` with a short body: the new grouping, shared folder names, and that open grouped PRs (check `gh pr list --author app/renovate`) will be superseded.
- [ ] **Step 3:** Run `gh pr checks --watch`. Expected: the `validate` job passes.
