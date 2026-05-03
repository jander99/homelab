# learnings.md — nx-cdk8s-init

## 2026-05-03 Session Start

### Repo State
- **Branch**: feature/nx-cdk8s-init (off master)
- **Clean slate**: No package.json, nx.json, .yarnrc.yml, tsconfig.base.json at repo root
- **Only untracked**: .sisyphus/ directory
- **k3s/ is untouched**: Must remain so throughout

### Key Constraints (NEVER VIOLATE)
1. `nodeLinker: node-modules` MUST be in .yarnrc.yml BEFORE first yarn install
2. Do NOT use `cdk8s init typescript-app` — creates conflicting package.json
3. Do NOT modify anything under k3s/
4. Do NOT add NX Cloud or ESLint
5. Yarn 4.x version: use `npm view @yarnpkg/cli-dist version` (NOT `npm show yarn version`)
6. Default synth output → `applications/cdk8s/dist/` (staging, NOT k3s/applications/)
7. CDK8S_OUTDIR env var overrides at invocation time (escape hatch)

### Task 1 Verification
- Created `.yarnrc.yml` with exactly `nodeLinker: node-modules`.
- Appended Node/NX/CDK8s ignores to `.gitignore` without overwriting existing lines.
- Created root `package.json` with `packageManager: yarn@4.14.1`, `workspaces: ["applications/*"]`, and `nx: latest`.
- Verified file contents directly; JSON/ignore files have no configured LSP diagnostics in this workspace.

### Task 2: Root NX/TypeScript config
- Created exact-root `nx.json` and `tsconfig.base.json` with no NX Cloud config.
- JSON validation passed with `python3 -c "import json; json.load(...)"`.
- `nx.json` cloud-reference grep returned `NX_CLOUD_ABSENT`.
- `lsp_diagnostics` reported only missing Biome server, unrelated to the JSON contents.

## Task 3 — Yarn Install + cdk8s App Scaffold

### npm package versions pinned (2026-05-02)
- `cdk8s`: 2.70.59 → `^2.70.59`
- `cdk8s-cli`: 2.206.10 → `^2.206.10`
- `constructs`: 10.6.0 → `^10.6.0`
- `ts-node`: `^10.9.2` (pinned per template)
- `typescript`: `~5.4.5` (pinned per template)

### Yarn 4 activation
- System had Yarn 1.22.22 installed via nvm global modules
- `corepack` was NOT available in `$PATH` (not bundled with node v25.2.1 in nvm, or removed)
- Fix: `npm install -g corepack --force` (force needed because yarn 1.x occupied the bin slot)
- Then: `corepack enable && corepack prepare yarn@4.14.1 --activate`
- `yarn --version` → `4.14.1` ✓

### yarn install warnings (non-fatal)
- `YN0002`: `@types/node` peer dep missing — ts-node requires it, not provided by workspace. Add `@types/node` to `devDependencies` in a future task if needed.
- `YN0004`: nx build scripts disabled (expected in clean workspace setup)
- **Exit 0** — install succeeded

### Files created
- `applications/cdk8s/package.json`
- `applications/cdk8s/tsconfig.json` (extends `../../tsconfig.base.json`)
- `applications/cdk8s/cdk8s.yaml` (`language: typescript`, `app: ts-node src/main.ts`, `output: dist`)
- `applications/cdk8s/src/` (empty placeholder dir)

### Evidence files
- `.sisyphus/evidence/task-3-yarn-install.txt`
- `.sisyphus/evidence/task-3-nodelinker-guard.txt` → `nodeLinker: node-modules`
- `.sisyphus/evidence/task-3-cdk8syaml.txt` → `output: dist`


## Task 4 — NX Project Config
- Created `applications/cdk8s/project.json` exactly with `synth`, `validate`, and `diff` targets using `nx:run-commands`.
- Verified `npx nx show project cdk8s --json` succeeded and returned the `cdk8s` project with all 3 targets.
- Confirmed no NX Cloud references: grep returned `CLEAN`.
- Recorded evidence in `.sisyphus/evidence/task-4-nx-show.txt` and `.sisyphus/evidence/task-4-no-cloud.txt`.
- Note: `lsp_diagnostics` is currently blocked by missing Biome installation in the workspace, unrelated to `project.json`.

## Task 5 — Hello-world Chart
- Added `applications/cdk8s/src/main.ts` using `ApiObject` only from `cdk8s` core; no `cdk8s import k8s` was needed.
- Added `@types/node` to `applications/cdk8s/package.json` so `process.env.CDK8S_OUTDIR` type-checks cleanly.
- `yarn install` completed successfully after adding the missing node types peer dependency.
- `npx nx run cdk8s:synth` produced `applications/cdk8s/dist/hello.k8s.yaml` with a Namespace named `hello-cdk8s`.
- `lsp_diagnostics` on `applications/cdk8s/src/main.ts` returned no diagnostics.
- `git diff -- k3s/` stayed empty; no files under `k3s/` were changed.
- `CDK8S_OUTDIR=/tmp/cdk8s-test` redirected synth output as expected when rerun with cache bypass.
