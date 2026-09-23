# Infrastructure

This repo is a disaster-recovery procedure. If a region vanishes, re-running
what is committed here brings the whole stack back as it was. Judge every
change on two questions: can it be replayed onto an empty account, and how
hard is it to upgrade later. Prefer declarative, version-pinned, re-runnable
mechanisms. A README step that nothing executes is the weakest form a step can
take, so name it as a liability rather than accept it.

## Layout

- `template/` Terraform modules, one per resource kind (`doks`, `zone`, `r2`,
  `linode-for-email`).
- `staging/`, `production/` Terraform roots. `config.yaml` in each is the one
  source of truth for that environment, read by `main.tf` and by helmfile.
- `cluster/` everything that runs on the DOKS cluster, as helmfile releases.
  Terraform owns the cluster, helmfile owns what is inside it. Its `README.md`
  holds the Restore procedure, `secrets.md` the 1Password items.
- `instance/` per-environment env files, gitignored, documented in its
  `README.md`.
- `scripts/` mise tasks. `mise tasks` lists them.
- `tmp-for-ref-will-be-rm/` scratch and old experiments. Not part of the
  procedure, do not build on it.

## Running things

- `mise install` provides every tool. Add tools to `mise.toml`, never assume
  they are on the machine.
- `mise run kubeconfig <env>` points kubectl at that environment's cluster.
- `mise run charts <env> [helmfile args]` runs helmfile with the environment's
  env file loaded. Default is `diff`. `-l name=<release>` selects one release.
- Terraform runs in CI (`.github/workflows/apply-<env>.yml`) with throwaway
  state: every run imports existing resources with
  `scripts/import-resources.sh`, then plans and applies.

## Working agreement

- Reads against the cluster and cloud accounts are free: `kubectl get`,
  `helm list`, `helmfile diff`, `helmfile template`, dry runs.
- Anything that changes cluster or cloud state is the user's to run:
  `kubectl apply`, `helmfile apply` or `sync`, `terraform apply`, and the mise
  tasks wrapping them. Output the exact command with what it does and why,
  and stop. "Install X" is a decision, not permission to run it. Only an
  explicit "run it yourself" in the same request is.
- Verify with reads before handing a command over, and again after the user
  reports it done. Render the release and read the objects it produces, since
  a clean diff can hide a `RollingUpdate` on a single-writer volume.
- One step is one commit, small enough to stand alone. Stage what the step
  adds and nothing from later steps. The user commits.
- Commit subjects are `<emoji> [type] subject`, as in `git log`: `✨ [feat]`,
  `🗄 [chore]`, `🛠 [fix]`. Bodies say why. No tool attribution lines.
- When a README or `secrets.md` describes something a change makes untrue,
  fix it in the same step.
