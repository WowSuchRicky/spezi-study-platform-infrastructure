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
- Naming is currently hardcoded to `spezistudyplatform` / `SpeziStudyPlatform`
  throughout (namespace, ConfigMaps, Secrets, Keycloak realm/roles, GCP
  project/cluster names, image refs — ~240 occurrences). This is intentional
  for the live deployment; don't "clean it up" piecemeal. If asked to fork
  this repo into a starter for a different study/app, use
  `tools/rename-project.sh` instead of manual find-and-replace — it handles
  the full set of casing variants in one pass and is dry-run-able.
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
