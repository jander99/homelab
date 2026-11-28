# Renovate: one PR per k3s folder

## Intent
Safer merge and rollback: reverting one service's bad update must not undo others.

## Goals / non-goals
- Goal: k3s updates are split by folder name (e.g. sonarr, loki).
- Non-goals: grouping by Kubernetes namespace; changing Docker (still ignored), Ansible, npm or GitHub Actions grouping.
- Anti-goals: the k3s pin splitting into two PRs; automerge.

## Approaches
1. **Per folder (chosen):** one template rule; new apps covered automatically; most PRs.
2. **Per namespace:** fewer PRs, but a hand-written rule per namespace, and shared namespaces (`media`) revert together.

## Design (`renovate.json`)
- Replace the `flux-infra-controllers`, `flux-infra-configs`, `flux-applications` and `kubernetes-images` rules with one rule:
  `matchFileNames: ["k3s/applications/**", "k3s/infrastructure/**"]`, `groupName: "k3s-workloads"`, `additionalBranchPrefix: "{{parentDir}}-"`.
- After it, the `k3s-io/k3s` rule resets `additionalBranchPrefix` to `""` so `plan.yaml` and `group_vars/all.yml` stay in one PR.
- Folders with the same name share a PR (authentik, cert-manager, kopiur, monitoring).

## Proposed (not yet discussed)
- Add `**/migration/**` to `ignorePaths`. These hold one-off manifests (`alpine` pins) that would otherwise form a `migration` PR mixing services.
- Raise `prConcurrentLimit` from 10 to 25; keep `prHourlyLimit` 5 and the Monday schedule.

## Constraints / left to the builder
- PR titles must name the folder, and major updates must stay distinguishable.
- Verify with `renovate-config-validator` and a Renovate dry run: expected branches, single k3s branch.
- Open grouped PRs (e.g. #483) are expected to be superseded after merge.
