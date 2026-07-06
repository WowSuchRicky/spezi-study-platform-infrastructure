<!--

This source file is part of the Stanford Spezi open source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

@AGENTS.md

## Working in this repo (Claude-specific notes)

- This is a GitOps repo: editing a manifest doesn't deploy anything by
  itself. Dev only picks up changes after `git push` (ArgoCD polls the
  branch); there's no local `kubectl apply` loop for app code here.
- Before claiming a change is correct, run `make validate` (kustomize build)
  and `make lint` (kubeconform) — both are cheap, fast, and exactly what CI
  runs (`.github/workflows/validate.yaml`).
- `make dev` requires a KIND cluster and a pushed branch; don't assume a
  cluster is available in this environment. If you need to sanity-check
  rendered YAML, `kubectl kustomize <overlay>` works without a live cluster.
- The four Kustomize trees (`apps/`, `infrastructure/`, `bootstrap/`,
  `argocd-apps/`) each have `base/` + `dev/` + `prod/`. When changing
  anything in `base/`, check whether `dev/patches/` or `prod/patches/`
  override the same field — patches are easy to miss and will silently mask
  a base change in one environment but not the other.
- This repo ships as a placeholder template (~80 files use `app-name-placeholder` /
  `app-name-pascal-placeholder` / `app-name-kebab-placeholder` / `registry-org-placeholder` /
  `repo-url-placeholder` / `domain-placeholder`), not a deployable app. It does not work
  until `tools/init-project.sh <app-name> [options]` has been run — that's
  enforced by a guard in `tools/setup.py` (and mirrored in `Makefile`'s
  `check-rendered` target) that scans all tracked files and refuses to run
  `make dev`/`make prod-bootstrap` if any placeholder remains.
  `make validate`/`make lint` still pass against the unrendered template
  (they only check Kustomize syntax/schema, not real names).
- Never hand-write a real app name into a manifest in this repo — use the
  placeholder tokens above, consistent with everywhere else. If you add a
  file that needs a new per-deployment value with no existing token, add a
  new `__TOKEN__`, and wire it into the substitution lists in both
  `tools/init-project.sh` and the guard regex in `tools/setup.py` (they're
  intentionally kept in sync, not derived from a shared source).
- `tools/init-project.sh` and `tools/setup.py` both exclude themselves *and
  each other* from placeholder scanning — they each contain the literal
  token strings in their own usage text / detection regex, and substituting
  through them would corrupt that source. Don't remove the exclusion when
  editing either file.
- To scaffold a new workload (another backend service, a new frontend, a
  worker), use the `spezi-new-app` skill (`.claude/skills/spezi-new-app/`)
  rather than improvising — it encodes the base/dev/prod + NetworkPolicy
  wiring this repo expects for every workload.
- Secrets never live in this repo. Dev secrets come from
  `infrastructure/dev/vault-seed-jobs.yaml`; prod secrets come from a real
  Vault via `ClusterSecretStore` (`infrastructure/prod/cluster-secret-store.yaml`).
  Don't add plaintext secrets to any manifest, including "dev-only" ones.
- `infrastructure/base/network-policies.yaml` default-denies all ingress and
  egress in the platform namespace. Any new cross-pod traffic path needs an
  explicit `NetworkPolicy` pair or it will be silently dropped at runtime
  (not at `kubectl apply` time — this fails quietly).
