# NX + cdk8s Monorepo Initialization

## TL;DR

> **Quick Summary**: Initialize the homelab repo as an NX monorepo using corepack-managed yarn, scaffold a minimal cdk8s TypeScript project at `applications/cdk8s/`, and produce a hello-world Kubernetes manifest to a configurable staging directory (`dist/` by default) that is completely separate from the Flux-managed `k3s/applications/` path.
>
> **Deliverables**:
> - Root `package.json` with corepack `packageManager` field and yarn workspaces
> - `.yarnrc.yml` with `nodeLinker: node-modules` (cdk8s PnP incompatibility guard)
> - `nx.json` + `tsconfig.base.json` at repo root
> - `applications/cdk8s/` — NX project with `package.json`, `tsconfig.json`, `cdk8s.yaml`, `project.json`
> - `applications/cdk8s/src/main.ts` — hello-world chart (one Namespace via `ApiObject`, no k8s import needed)
> - `.gitignore` additions for Node/NX artifacts
> - Verified: `nx run cdk8s:synth` writes YAML to `applications/cdk8s/dist/`; env var override works
>
> **Estimated Effort**: Short
> **Parallel Execution**: YES — 2 waves
> **Critical Path**: T1 → T3 → T5 → F3

---

## Context

### Original Request
Initialize this repo for NX, cdk8s, and TypeScript using corepack-managed yarn (latest). Produce a minimal cdk8s hello-world whose output goes to a configurable staging directory — NOT to `k3s/applications/` (the Flux-watched rendered-manifests directory). The user wants to inspect generated YAMLs before manually promoting them to the Flux path.

### Interview Summary
**Key Discussions**:
- **Output path**: User explicitly wants a staging directory (default `dist/`), NOT `k3s/applications/`. The architecture doc (`k3s/k3s.md`) says synth output eventually goes to `k3s/applications/`, but the user wants safety while learning cdk8s — nothing lands in Flux territory until they manually promote it.
- **App path**: `applications/cdk8s/` — matches `k3s/k3s.md` blueprint exactly.
- **Configurable output**: Via `CDK8S_OUTDIR` environment variable; default is `dist/` (relative to `applications/cdk8s/`).
- **No `cdk8s init typescript-app`**: The CLI init creates a conflicting standalone `package.json`. Manual scaffold into the NX workspace instead.
- **Minimum viable chart**: A single `ApiObject` emitting a `Namespace` — no `cdk8s import k8s` required, avoids generating ~10k lines of TypeScript.
- **Tests**: None needed — this is an infra codegen tool, not application code.

**Research Findings**:
- No existing Node.js/NX config — clean slate, no conflicts.
- cdk8s CLI is incompatible with Yarn PnP; `nodeLinker: node-modules` is mandatory.
- NX has no official cdk8s plugin; manual `project.json` with `nx:run-commands` executor is the pattern.
- `App.outdir` in `main.ts` controls where YAML is written; env var interpolation in `main.ts` makes it configurable.
- `cdk8s.yaml output:` mirrors `App.outdir` for CLI-level consistency.

### Metis Review
**Identified Gaps** (addressed):
- App path must be `applications/cdk8s/` (not `apps/k8s-manifests/`) per `k3s/k3s.md` — resolved.
- `.yarnrc.yml` must exist with `nodeLinker: node-modules` BEFORE `yarn install` — task ordering enforces this.
- Do NOT run `cdk8s init typescript-app` inside NX workspace — manual scaffold planned instead.
- `k3s/applications/kustomization.yaml` stays as-is (stub with `resources: []`) — out of scope.
- `.gitignore` must be updated before NX init to prevent committing `node_modules` and `.nx/cache`.
- `imports/` directory (from `cdk8s import k8s`) should be gitignored — it's regenerable.

---

## Work Objectives

### Core Objective
Bootstrap the repo with NX + cdk8s TypeScript tooling so that `nx run cdk8s:synth` produces valid Kubernetes YAML in a staging directory, reviewable before any Flux reconciliation.

### Concrete Deliverables
- `package.json` (repo root) — yarn workspace root, corepack pinned, nx devDependency
- `.yarnrc.yml` (repo root) — `nodeLinker: node-modules`
- `nx.json` (repo root) — NX workspace config with caching
- `tsconfig.base.json` (repo root) — shared TypeScript base config
- `.gitignore` (updated) — Node/NX/dist additions
- `applications/cdk8s/package.json` — cdk8s app dependencies
- `applications/cdk8s/tsconfig.json` — extends root base
- `applications/cdk8s/cdk8s.yaml` — cdk8s CLI config, `output: dist`
- `applications/cdk8s/project.json` — NX targets: `synth`, `validate`, `diff`
- `applications/cdk8s/src/main.ts` — hello-world chart (Namespace via ApiObject)
- `applications/cdk8s/dist/hello.k8s.yaml` — synthesized output (gitignored)

### Definition of Done
- [ ] `yarn --version` matches the `packageManager` field in `package.json`
- [ ] `nx show project cdk8s` exits 0 and lists `synth`, `validate`, `diff` targets
- [ ] `nx run cdk8s:synth` exits 0
- [ ] `applications/cdk8s/dist/*.yaml` exists after synth
- [ ] `kubectl --dry-run=client -f applications/cdk8s/dist/ --recursive` exits 0
- [ ] `CDK8S_OUTDIR=/tmp/cdk8s-test nx run cdk8s:synth` writes YAML to `/tmp/cdk8s-test/`, NOT to `applications/cdk8s/dist/`
- [ ] `k3s/` directory tree is unchanged (no new files, no edits)

### Must Have
- Yarn managed via corepack (`packageManager` field in `package.json`)
- `nodeLinker: node-modules` in `.yarnrc.yml` (before first install)
- `applications/cdk8s/` as the NX project root (per `k3s/k3s.md` blueprint)
- Default synth output to `applications/cdk8s/dist/` (staging, not Flux territory)
- Configurable output via `CDK8S_OUTDIR` env var
- At least one valid Kubernetes YAML file produced by synth
- `kubectl --dry-run` validation passes on output

### Must NOT Have (Guardrails)
- **NO files written under `k3s/`** — Flux config and rendered-manifests directories are untouched
- **NO `cdk8s init typescript-app`** — would create conflicting standalone package.json
- **NO Yarn PnP** — `nodeLinker: node-modules` is mandatory for cdk8s CLI
- **NO NX Cloud** — skip/decline during any interactive NX init prompt
- **NO ESLint/Prettier setup** — out of scope for hello-world
- **NO `cdk8s import k8s`** during hello-world — avoid 10k+ lines of generated TypeScript; use `ApiObject` instead
- **NO modifications to existing files under `k3s/`** — including `k3s/applications/kustomization.yaml`

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: NO
- **Automated tests**: None — infra codegen tool
- **Agent-Executed QA**: YES (mandatory for all tasks)

### QA Policy
All verification is agent-executable. The executing agent runs commands and captures terminal output as evidence.

- **CLI tool verification**: `bash` — `yarn`, `nx`, `cdk8s` commands with exit codes
- **File existence**: `bash` — `ls` / `find` on expected output paths
- **YAML validity**: `bash` — `kubectl --dry-run=client` on synthesized output
- **Negative tests**: verify `k3s/` is unchanged, verify env var redirect works

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — parallel, no dependencies):
├── Task 1: Root tooling files (package.json, .yarnrc.yml, .gitignore update)  [quick]
└── Task 2: NX + TS config files (nx.json, tsconfig.base.json)                [quick]

Wave 2 (After Wave 1 — cdk8s app scaffold + install):
└── Task 3: Yarn install + cdk8s app scaffold (package.json, tsconfig.json, cdk8s.yaml, src/) [unspecified-high]

Wave 3 (After Wave 2 — parallel, both need T3 scaffold):
├── Task 4: NX project.json (synth/validate/diff targets)  [quick]
└── Task 5: src/main.ts hello-world chart                  [quick]

Wave FINAL (After ALL tasks — 4 parallel reviews):
├── F1: Plan compliance audit (oracle)
├── F2: Code quality review (unspecified-high)
├── F3: Real QA — yarn install, nx run cdk8s:synth, kubectl dry-run (unspecified-high)
└── F4: Scope fidelity check — verify k3s/ is untouched (deep)
→ Present results → Get explicit user okay
```

### Dependency Matrix
- **T1**: none → T3
- **T2**: none → T3
- **T3**: T1, T2 → T4, T5
- **T4**: T3 → F1, F3
- **T5**: T3 → F1, F3
- **F1–F4**: T1–T5 (all)

### Agent Dispatch Summary
- **Wave 1**: 2 tasks → `quick`, `quick`
- **Wave 2**: 1 task → `unspecified-high`
- **Wave 3**: 2 tasks → `quick`, `quick`
- **Final**: 4 tasks → `oracle`, `unspecified-high`, `unspecified-high`, `deep`

---

## TODOs

---

- [x] 1. Root tooling files: `package.json`, `.yarnrc.yml`, `.gitignore`

  **What to do**:
  - Check current `.gitignore` — it currently has `**/*.env` and `.vscode/**`. Append the following lines (do NOT overwrite the file):
    ```
    # Node / NX
    node_modules/
    .yarn/cache/
    .yarn/install-state.gz
    .nx/cache/
    # CDK8s generated
    applications/cdk8s/dist/
    applications/cdk8s/imports/
    ```
  - Create `.yarnrc.yml` at repo root with EXACTLY this content (no other lines):
    ```yaml
    nodeLinker: node-modules
    ```
  - Run `npm view @yarnpkg/cli-dist version` to get the current stable Yarn 4.x version (do NOT use `npm show yarn version` — that returns Yarn 1.x). Create `package.json` at repo root:
    ```json
    {
      "name": "homelab",
      "private": true,
      "packageManager": "yarn@<LATEST_VERSION>",
      "workspaces": ["applications/*"],
      "devDependencies": {
        "nx": "latest"
      }
    }
    ```
  - Verify: `cat .yarnrc.yml` shows `nodeLinker: node-modules`; `cat package.json | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'packageManager' in d; assert 'workspaces' in d"` exits 0.

  **Must NOT do**:
  - Do NOT run `yarn install` yet — that happens in T3 after `nx.json` exists
  - Do NOT run `corepack enable` — that is the developer's machine concern, not a repo file
  - Do NOT overwrite `.gitignore` — only append
  - Do NOT add any file under `k3s/`

  **Recommended Agent Profile**:
  > Creating 3 config files and appending to an existing file. Pure file I/O.
  - **Category**: `quick`
    - Reason: No logic, no installs, just writing well-defined config files
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Task 3 (yarn install needs `.yarnrc.yml` and `package.json`)
  - **Blocked By**: None (can start immediately)

  **References**:
  - `.gitignore` (repo root) — existing file to append to, not overwrite
  - `k3s/k3s.md` — confirm `applications/cdk8s/` is the correct workspace path (architecture blueprint)
  - Yarn docs: `nodeLinker: node-modules` is a single-line `.yarnrc.yml` that disables PnP

  **Acceptance Criteria**:
  - [ ] `.yarnrc.yml` exists at repo root and contains exactly `nodeLinker: node-modules`
  - [ ] `package.json` exists at repo root with `packageManager`, `workspaces`, and `devDependencies.nx` fields
  - [ ] `.gitignore` contains `node_modules/` and `applications/cdk8s/dist/`

  **QA Scenarios**:
  ```
  Scenario: All three files exist with correct content
    Tool: Bash
    Steps:
      1. Run: grep -c 'nodeLinker: node-modules' .yarnrc.yml
         Assert: output is 1
      2. Run: python3 -c "import json; d=json.load(open('package.json')); print(d['packageManager'], d['workspaces'])"
         Assert: exits 0, prints a yarn@4.x.x version and ['applications/*']
      3. Run: grep 'node_modules' .gitignore && grep 'applications/cdk8s/dist' .gitignore
         Assert: both lines found (exit 0)
    Expected Result: All three assertions pass
    Evidence: .sisyphus/evidence/task-1-files-exist.txt

  Scenario: .yarnrc.yml is NOT missing (guard against PnP mode)
    Tool: Bash
    Steps:
      1. Run: test -f .yarnrc.yml && echo EXISTS || echo MISSING
         Assert: output is EXISTS
    Expected Result: File exists before any yarn command is run
    Evidence: .sisyphus/evidence/task-1-yarnrc-guard.txt
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-1-files-exist.txt` — combined output of grep/python3 checks
  - [ ] `.sisyphus/evidence/task-1-yarnrc-guard.txt` — file existence check

  **Commit**: YES (groups with T2)
  - Message: `chore(nx): initialize NX monorepo with corepack yarn`
  - Files: `package.json`, `.yarnrc.yml`, `.gitignore`

---

- [x] 2. NX + TypeScript config: `nx.json`, `tsconfig.base.json`

  **What to do**:
  - Create `nx.json` at repo root:
    ```json
    {
      "$schema": "./node_modules/nx/schemas/nx-schema.json",
      "workspaceLayout": {
        "appsDir": "applications",
        "libsDir": "applications"
      },
      "targetDefaults": {
        "synth": {
          "cache": true
        }
      },
      "defaultBase": "master"
    }
    ```
  - Create `tsconfig.base.json` at repo root:
    ```json
    {
      "compileOnSave": false,
      "compilerOptions": {
        "rootDir": ".",
        "sourceMap": true,
        "declaration": false,
        "moduleResolution": "node",
        "emitDecoratorMetadata": true,
        "experimentalDecorators": true,
        "target": "ES2020",
        "module": "CommonJS",
        "lib": ["ES2020"],
        "skipLibCheck": true,
        "skipDefaultLibCheck": true,
        "baseUrl": "."
      },
      "exclude": ["node_modules", "tmp"]
    }
    ```
  - Validate JSON syntax: `python3 -c "import json; json.load(open('nx.json'))"` and same for `tsconfig.base.json`.

  **Must NOT do**:
  - Do NOT add `tasksRunnerOptions.default.runner` pointing to NX Cloud
  - Do NOT add ESLint, Prettier, or any plugin configuration
  - Do NOT touch anything under `k3s/`

  **Recommended Agent Profile**:
  > Creating 2 JSON config files. Pure file I/O with JSON structure.
  - **Category**: `quick`
    - Reason: No logic, no installs, just writing well-defined JSON config files
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: None (can start immediately)

  **References**:
  - `k3s/k3s.md` lines 128-152 — NX workspace layout and target definitions blueprint
  - NX docs: `workspaceLayout.appsDir` controls where NX looks for projects

  **Acceptance Criteria**:
  - [ ] `nx.json` exists with `workspaceLayout.appsDir = "applications"`
  - [ ] `tsconfig.base.json` exists with `module: "CommonJS"` and `target: "ES2020"`
  - [ ] Both files are valid JSON (python3 parse check exits 0)

  **QA Scenarios**:
  ```
  Scenario: Config files are valid JSON with required fields
    Tool: Bash
    Steps:
      1. Run: python3 -c "import json; d=json.load(open('nx.json')); assert d['workspaceLayout']['appsDir']=='applications'; print('OK')"
         Assert: prints OK
      2. Run: python3 -c "import json; d=json.load(open('tsconfig.base.json')); assert d['compilerOptions']['module']=='CommonJS'; print('OK')"
         Assert: prints OK
    Expected Result: Both assertions pass, both are valid parseable JSON
    Evidence: .sisyphus/evidence/task-2-config-valid.txt

  Scenario: No NX Cloud config present
    Tool: Bash
    Steps:
      1. Run: grep -r 'nxcloud\|nx-cloud\|cloud.nx.app' nx.json || echo 'CLEAN'
         Assert: output is CLEAN
    Expected Result: No NX Cloud references
    Evidence: .sisyphus/evidence/task-2-no-cloud.txt
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-2-config-valid.txt`
  - [ ] `.sisyphus/evidence/task-2-no-cloud.txt`

  **Commit**: YES (groups with T1)
  - Message: `chore(nx): initialize NX monorepo with corepack yarn`
  - Files: `nx.json`, `tsconfig.base.json`

---

- [x] 3. Yarn install + cdk8s app scaffold

  **What to do**:
  - Create directory `applications/cdk8s/src/`.
  - Create `applications/cdk8s/package.json`:
    ```json
    {
      "name": "cdk8s",
      "version": "0.0.1",
      "private": true,
      "main": "src/main.ts",
      "scripts": {
        "synth": "cdk8s synth"
      },
      "dependencies": {
        "cdk8s": "^2.68.0",
        "constructs": "^10.3.0"
      },
      "devDependencies": {
        "cdk8s-cli": "^2.198.0",
        "ts-node": "^10.9.2",
        "typescript": "~5.4.5"
      }
    }
    ```
    > Before writing versions, check latest: `npm show cdk8s version`, `npm show cdk8s-cli version`, `npm show constructs version`. Substitute actual latest semver ranges.
  - Create `applications/cdk8s/tsconfig.json`:
    ```json
    {
      "extends": "../../tsconfig.base.json",
      "compilerOptions": {
        "outDir": "../../dist/out-tsc",
        "types": ["node"]
      },
      "include": ["src/**/*.ts"]
    }
    ```
  - Create `applications/cdk8s/cdk8s.yaml`:
    ```yaml
    language: typescript
    app: ts-node src/main.ts
    output: dist
    ```
    > `output: dist` is the staging directory default. The env var `CDK8S_OUTDIR` overrides this at runtime via `main.ts` — NOT via this file. Both must agree on `dist` as the default.
  - From the **repo root**, run `yarn install`. This installs NX and all workspace packages.
  - Verify: `node_modules/` appears at repo root and `applications/cdk8s/node_modules/` is symlinked or present.
  - Verify: `yarn --version` output matches the `packageManager` field from `package.json`.

  **Must NOT do**:
  - Do NOT run `cdk8s init typescript-app` — it creates a conflicting standalone package.json
  - Do NOT set `nodeLinker` to anything other than `node-modules` (PnP will break cdk8s CLI)
  - Do NOT add an `imports:` section to `cdk8s.yaml` — defers `cdk8s import k8s` to a later task
  - Do NOT touch anything under `k3s/`

  **Recommended Agent Profile**:
  > Creates 4 files, checks npm for latest versions, runs yarn install. Needs bash + file I/O.
  - **Category**: `unspecified-high`
    - Reason: Requires live npm version lookup + yarn install execution + output verification
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (sequential, after both T1 and T2 complete)
  - **Blocks**: Task 4, Task 5 (both need the scaffold and node_modules)
  - **Blocked By**: Task 1 (`.yarnrc.yml`, `package.json`), Task 2 (`nx.json`)

  **References**:
  - `package.json` (repo root, from T1) — workspace root that yarn install reads
  - `.yarnrc.yml` (repo root, from T1) — must exist before install or PnP activates
  - `nx.json` (from T2) — must exist before NX can discover projects
  - cdk8s docs: `cdk8s.yaml` language/app/output fields
  - cdk8s docs: `App.outdir` is respected over `cdk8s.yaml output:` when set in code

  **Acceptance Criteria**:
  - [ ] `applications/cdk8s/package.json` exists with valid JSON
  - [ ] `applications/cdk8s/tsconfig.json` has `"extends": "../../tsconfig.base.json"`
  - [ ] `applications/cdk8s/cdk8s.yaml` has `output: dist`
  - [ ] `yarn --version` matches `packageManager` field in root `package.json`
  - [ ] `node_modules/` exists at repo root after install

  **QA Scenarios**:
  ```
  Scenario: Yarn install succeeds and version matches packageManager field
    Tool: Bash
    Steps:
      1. Run from repo root: yarn install 2>&1 | tail -5
         Assert: exits 0, no error lines
      2. Run: yarn --version
         Assert: output matches version in packageManager field of package.json
         (e.g. if packageManager is yarn@4.5.3, output should be 4.5.3)
    Expected Result: Install succeeds, version pin confirmed
    Evidence: .sisyphus/evidence/task-3-yarn-install.txt

  Scenario: nodeLinker is NOT pnp (guard against broken cdk8s install)
    Tool: Bash
    Steps:
      1. Run: cat .yarnrc.yml | grep nodeLinker
         Assert: output contains 'node-modules'
      2. Run: test -d node_modules && echo EXISTS || echo MISSING
         Assert: EXISTS
    Expected Result: node-modules linker active, node_modules dir present
    Evidence: .sisyphus/evidence/task-3-nodelinker-guard.txt

  Scenario: cdk8s.yaml has correct output field
    Tool: Bash
    Steps:
      1. Run: python3 -c "import yaml; d=yaml.safe_load(open('applications/cdk8s/cdk8s.yaml')); assert d['output']=='dist'; print('OK')"
         Assert: prints OK
    Expected Result: output field is 'dist'
    Evidence: .sisyphus/evidence/task-3-cdk8syaml.txt
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-3-yarn-install.txt`
  - [ ] `.sisyphus/evidence/task-3-nodelinker-guard.txt`
  - [ ] `.sisyphus/evidence/task-3-cdk8syaml.txt`


  **Commit**: NO (bundled into T5 commit after all scaffold files exist)

---

- [x] 4. NX project config: `applications/cdk8s/project.json`

  **What to do**:
  - Create `applications/cdk8s/project.json`:
    ```json
    {
      "name": "cdk8s",
      "$schema": "../../node_modules/nx/schemas/project-schema.json",
      "sourceRoot": "applications/cdk8s/src",
      "projectType": "application",
      "targets": {
        "synth": {
          "executor": "nx:run-commands",
          "options": {
            "command": "cdk8s synth",
            "cwd": "applications/cdk8s"
          }
        },
        "validate": {
          "executor": "nx:run-commands",
          "options": {
            "command": "kubectl --dry-run=client apply -f dist/ --recursive",
            "cwd": "applications/cdk8s"
          }
        },
        "diff": {
          "executor": "nx:run-commands",
          "options": {
            "command": "kubectl diff -f dist/ --recursive",
            "cwd": "applications/cdk8s"
          }
        }
      },
      "tags": []
    }
    ```
    > NOTE: `synth` intentionally does NOT pass `CDK8S_OUTDIR`. The env var is an **escape hatch** controlled by the developer at invocation time. Default output comes from `main.ts` (`process.env.CDK8S_OUTDIR ?? 'dist'`).
    > `validate` and `diff` reference `dist/` (relative to `applications/cdk8s/`) which matches the default synth output.
  - After writing, verify NX picks up the project: `npx nx show project cdk8s` (must exit 0 and show 3 targets).

  **Must NOT do**:
  - Do NOT add a `production` configuration pointing to `k3s/applications/` — that is for a future manual-promote workflow
  - Do NOT add an `import` target (deferred)
  - Do NOT add NX Cloud, caching plugins, or executors other than `nx:run-commands`

  **Recommended Agent Profile**:
  > Creating one JSON file, then running an NX CLI command to verify project discovery.
  - **Category**: `quick`
    - Reason: Single file creation + one verification command
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 5)
  - **Blocks**: Final Verification Wave
  - **Blocked By**: Task 3 (needs `node_modules/` for `nx` binary and `$schema` resolution)

  **References**:
  - `k3s/k3s.md` lines 128-152 — the authoritative `project.json` skeleton and target name definitions
  - `nx.json` (from T2) — `workspaceLayout.appsDir: applications` means NX discovers `applications/*/project.json`
  - NX docs: `nx:run-commands` executor accepts `command` (string) and `cwd` (relative to repo root)

  **Acceptance Criteria**:
  - [ ] `applications/cdk8s/project.json` exists and is valid JSON
  - [ ] `npx nx show project cdk8s` exits 0
  - [ ] Output of `nx show project cdk8s` lists targets: `synth`, `validate`, `diff`

  **QA Scenarios**:
  ```
  Scenario: NX discovers cdk8s project and lists all three targets
    Tool: Bash
    Steps:
      1. Run: npx nx show project cdk8s --json 2>&1
         Assert: exits 0
      2. Run: npx nx show project cdk8s --json | python3 -c "import sys,json; d=json.load(sys.stdin); targets=list(d.get('targets',{}).keys()); [print(t) for t in targets]; assert 'synth' in targets and 'validate' in targets and 'diff' in targets, f'Missing targets: {targets}'"
         Assert: prints synth, validate, diff and exits 0
    Expected Result: NX project graph includes cdk8s with all three targets
    Evidence: .sisyphus/evidence/task-4-nx-show.txt

  Scenario: project.json contains no NX Cloud or forbidden executors
    Tool: Bash
    Steps:
      1. Run: grep -E 'nxcloud|@nx/cloud|nx-cloud' applications/cdk8s/project.json || echo 'CLEAN'
         Assert: CLEAN
    Expected Result: No NX Cloud references
    Evidence: .sisyphus/evidence/task-4-no-cloud.txt
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-4-nx-show.txt`
  - [ ] `.sisyphus/evidence/task-4-no-cloud.txt`

  **Commit**: YES (groups with T5)
  - Message: `feat(cdk8s): scaffold cdk8s TypeScript app with hello-world chart`
  - Files: `applications/cdk8s/**`

---

- [x] 5. Hello-world chart: `applications/cdk8s/src/main.ts`

  **What to do**:
  - Create `applications/cdk8s/src/main.ts` with the following content:
    ```typescript
    import { App, Chart, ApiObject } from 'cdk8s';
    import { Construct } from 'constructs';

    class HelloChart extends Chart {
      constructor(scope: Construct, id: string) {
        super(scope, id);

        new ApiObject(this, 'hello-namespace', {
          apiVersion: 'v1',
          kind: 'Namespace',
          metadata: {
            name: 'hello-cdk8s',
          },
        });
      }
    }

    const app = new App({
      outdir: process.env.CDK8S_OUTDIR ?? 'dist',
    });

    new HelloChart(app, 'hello');

    app.synth();
    ```
  - Run `npx nx run cdk8s:synth` from the repo root. Observe output directory.
  - Verify `applications/cdk8s/dist/` is created and contains at least one `.yaml` file.
  - Verify the YAML is valid Kubernetes: `kubectl --dry-run=client apply -f applications/cdk8s/dist/ --recursive`.
  - Test env var override: `CDK8S_OUTDIR=/tmp/cdk8s-test npx nx run cdk8s:synth` and verify YAML appears in `/tmp/cdk8s-test/` instead of `dist/`.
  - Run `git diff k3s/` and confirm it is empty (no changes under `k3s/`).

  **Must NOT do**:
  - Do NOT import from `cdk8s/lib/imports/k8s` or run `cdk8s import` — use `ApiObject` from cdk8s core only
  - Do NOT add `console.log` statements
  - Do NOT write to any path under `k3s/`

  **Recommended Agent Profile**:
  > Writing one TypeScript file then running 3 verification commands (synth, kubectl dry-run, env override test).
  - **Category**: `quick`
    - Reason: Minimal code file + sequential verification commands; no complex logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 4)
  - **Blocks**: Final Verification Wave
  - **Blocked By**: Task 3 (needs `node_modules/cdk8s`, `ts-node` installed)

  **References**:
  - `applications/cdk8s/package.json` (from T3) — confirms `cdk8s` and `constructs` are dependencies
  - `applications/cdk8s/cdk8s.yaml` (from T3) — `app: ts-node src/main.ts` is how cdk8s CLI invokes this file
  - cdk8s docs: `App.outdir` property — overrides `cdk8s.yaml output:` at runtime
  - cdk8s docs: `ApiObject` constructor signature — `{ apiVersion, kind, metadata }` shape

  **Acceptance Criteria**:
  - [ ] `applications/cdk8s/src/main.ts` exists
  - [ ] `npx nx run cdk8s:synth` exits 0
  - [ ] `applications/cdk8s/dist/*.yaml` exists after synth
  - [ ] `kubectl --dry-run=client apply -f applications/cdk8s/dist/ --recursive` exits 0
  - [ ] `CDK8S_OUTDIR=/tmp/cdk8s-test npx nx run cdk8s:synth && ls /tmp/cdk8s-test/` shows YAML, AND `applications/cdk8s/dist/` is NOT populated by this second run (verify with timestamp or diff)
  - [ ] `git diff k3s/` is empty

  **QA Scenarios**:
  ```
  Scenario: Default synth writes YAML to applications/cdk8s/dist/
    Tool: Bash
    Preconditions: applications/cdk8s/dist/ does NOT exist yet (or is empty)
    Steps:
      1. Run: npx nx run cdk8s:synth 2>&1
         Assert: exits 0, output mentions 'Synthesizing...' or similar
      2. Run: ls applications/cdk8s/dist/*.yaml 2>&1
         Assert: at least one .yaml file listed
      3. Run: cat applications/cdk8s/dist/*.yaml | head -20
         Assert: output contains 'apiVersion: v1' and 'kind: Namespace'
    Expected Result: Valid Namespace YAML in dist/
    Evidence: .sisyphus/evidence/task-5-synth-default.txt

  Scenario: kubectl dry-run validates synthesized YAML
    Tool: Bash
    Preconditions: previous scenario ran, dist/ contains YAML
    Steps:
      1. Run: kubectl --dry-run=client apply -f applications/cdk8s/dist/ --recursive 2>&1
         Assert: exits 0
         Assert: output contains 'namespace/hello-cdk8s configured (server dry run)' or 'created (dry run)'
    Expected Result: Kubernetes API accepts the YAML as valid
    Evidence: .sisyphus/evidence/task-5-kubectl-dryrun.txt

  Scenario: CDK8S_OUTDIR env var redirects output
    Tool: Bash
    Steps:
      1. Run: rm -rf /tmp/cdk8s-test
      2. Run: CDK8S_OUTDIR=/tmp/cdk8s-test npx nx run cdk8s:synth 2>&1
         Assert: exits 0
      3. Run: ls /tmp/cdk8s-test/*.yaml 2>&1
         Assert: at least one .yaml file in /tmp/cdk8s-test/
      4. Note mtime on applications/cdk8s/dist/ files (from previous scenario)
         Assert: mtime NOT updated (CDK8S_OUTDIR redirected away from dist/)
    Expected Result: YAML written to /tmp/cdk8s-test/, NOT to dist/
    Evidence: .sisyphus/evidence/task-5-env-override.txt

  Scenario: k3s/ directory is completely unchanged
    Tool: Bash
    Steps:
      1. Run: git diff k3s/ 2>&1
         Assert: empty output (no lines)
      2. Run: git status --porcelain k3s/ 2>&1
         Assert: empty output (no changes tracked or untracked under k3s/)
    Expected Result: Zero modifications to k3s/ directory tree
    Evidence: .sisyphus/evidence/task-5-k3s-unchanged.txt
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-5-synth-default.txt`
  - [ ] `.sisyphus/evidence/task-5-kubectl-dryrun.txt`
  - [ ] `.sisyphus/evidence/task-5-env-override.txt`
  - [ ] `.sisyphus/evidence/task-5-k3s-unchanged.txt`

  **Commit**: YES (groups with T3, T4)
  - Message: `feat(cdk8s): scaffold cdk8s TypeScript app with hello-world chart`
  - Files: `applications/cdk8s/**`
  - Pre-commit: `npx nx run cdk8s:synth` (verify synth still passes)
## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists. For each "Must NOT Have": search for forbidden patterns (any file under `k3s/` created or modified; PnP references; `cdk8s init` invocations; ESLint config). Verify evidence files exist.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `yarn tsc --noEmit` from `applications/cdk8s/`. Check `main.ts` for: unused imports, `any` types, stray `console.log`. Check all new JSON/YAML files for syntax validity (`node -e "JSON.parse(require('fs').readFileSync('...'))"` for JSON; `python3 -c "import yaml; yaml.safe_load(open('...'))"` for YAML). Check `.gitignore` additions are present.
  Output: `TypeCheck [PASS/FAIL] | JSON valid [N/N] | YAML valid [N/N] | VERDICT`

- [ ] F3. **Real QA** — `unspecified-high`
  Execute every QA scenario from every task. Start from a clean state. Run commands, capture output to `.sisyphus/evidence/final-qa/`. Confirm `k3s/` is unmodified via `git status`.
  Output: `Scenarios [N/N pass] | k3s unchanged [YES/NO] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  Compare each task's "What to do" against actual git diff. Verify nothing beyond scope was created. Check for cross-task contamination. Confirm `k3s/applications/kustomization.yaml` is unmodified.
  Output: `Tasks [N/N compliant] | Unaccounted changes [CLEAN/N] | VERDICT`

---

## Commit Strategy

- **1**: `chore(nx): initialize NX monorepo with corepack yarn` — `package.json`, `.yarnrc.yml`, `nx.json`, `tsconfig.base.json`, `.gitignore`
- **2**: `feat(cdk8s): scaffold cdk8s TypeScript app with hello-world chart` — `applications/cdk8s/**`

---

## Success Criteria

### Verification Commands
```bash
# Prove corepack works
yarn --version  # Expected: matches packageManager field

# Prove NX knows about the project
nx show project cdk8s  # Expected: JSON with synth/validate/diff targets

# Prove synth works (default staging output)
nx run cdk8s:synth  # Expected: exit 0

# Prove output landed in staging dir
ls applications/cdk8s/dist/  # Expected: *.yaml file(s)

# Prove valid K8s YAML
kubectl --dry-run=client -f applications/cdk8s/dist/ --recursive  # Expected: exit 0

# Prove env var override
CDK8S_OUTDIR=/tmp/cdk8s-test nx run cdk8s:synth && ls /tmp/cdk8s-test/  # Expected: YAML files there, NOT in dist/

# Prove k3s/ is untouched
git diff k3s/  # Expected: empty (no changes)
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] `yarn --version` matches `packageManager` field
- [ ] `nx show project cdk8s` lists 3 targets
- [ ] `nx run cdk8s:synth` produces valid YAML in staging dir
- [ ] `k3s/` directory: zero changes
