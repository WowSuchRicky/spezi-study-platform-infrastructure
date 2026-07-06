#
# This source file is part of the Stanford Spezi open source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

---
name: spezi-new-app
description: Scaffold a new workload (server-style or web-style) into this repo's apps/ Kustomize layout (base + dev/prod patches), wired into network policies and ArgoCD. Use when adding a new backend service or frontend to the platform, e.g. "add a new worker service" or "add an admin dashboard app".
---

# Adding a new app/workload

This repo deploys workloads under `apps/` using a `base` + per-environment
`patches` Kustomize pattern. There are two existing shapes to copy from:

- `apps/base/server/` — stateful, DB-backed service (migrate init container,
  DB credentials, Keycloak client secret via ExternalSecret).
- `apps/base/web/` — stateless static/SPA frontend (no secrets, no DB).

Pick whichever is the closer shape for the new workload and follow these
steps. Use `<name>` as the new workload's short identifier (e.g. `worker`,
`admin`).

Check `infrastructure/base/namespace.yaml` first: if it still says
`app-name-placeholder`, this repo is an unrendered template and every new resource
you write should use that same placeholder (`app-name-placeholder`,
`app-name-pascal-placeholder`, `app-name-kebab-placeholder`, `registry-org-placeholder`), exactly
like the existing `server`/`web` manifests — not a literal name. If it's a
real name, this is a rendered fork; use that real name instead.

## 1. Create `apps/base/<name>/`

Copy the closer-matching existing directory (`server/` or `web/`) and adjust:

- `deployment.yaml` — rename `metadata.name`, `spec.selector.matchLabels.app`,
  container name, and `image:` (use `ghcr.io/registry-org-placeholder/app-name-placeholder-<name>:latest`
  on the template, or the rendered equivalent on a fork).
  Keep `securityContext` hardening (`runAsNonRoot`, `allowPrivilegeEscalation:
  false`, dropped capabilities) — every workload in this repo runs that way.
- `service.yaml` — rename `metadata.name` and `spec.selector.app`.
- `configmap.yaml` — rename `metadata.name`, keep only env vars the new
  workload actually needs.
- `service-account.yaml` — rename `metadata.name`; keep
  `automountServiceAccountToken: false` unless the workload calls the K8s API.
- `external-secret.yaml` — only if the workload needs secrets from Vault.
  Follow `apps/base/server/external-secret.yaml`'s `secretStoreRef` /
  `remoteRef` pattern.
- `kustomization.yaml` — list the files you created (see
  `apps/base/server/kustomization.yaml` for the shape).

All resources go in the platform's single namespace (`app-name-placeholder` on the
template, or whatever `infrastructure/base/namespace.yaml` says on a
rendered fork) — this repo does not split workloads across namespaces.

## 2. Register the new directory

Add `<name>/` to the `resources:` list in `apps/base/kustomization.yaml`.

## 3. Add dev/prod overrides

Even a workload with no env-specific differences needs an entry so the
overlay is explicit:

- `apps/dev/patches/<name>-deployment.yaml` — typically lower
  replicas/resources, `imagePullPolicy` left default.
- `apps/prod/patches/<name>-deployment.yaml` — `RollingUpdate` strategy,
  `imagePullPolicy: Always`, real resource requests/limits.
- `apps/dev/patches/<name>-configmap.yaml` / `apps/prod/patches/<name>-configmap.yaml`
  for any env-specific config (e.g. `APP_ENVIRONMENT`).
- Reference each new patch file from `apps/dev/kustomization.yaml` and
  `apps/prod/kustomization.yaml` under `patches:`.
- If the workload should survive node disruption in prod, add a
  `PodDisruptionBudget` entry to `apps/prod/pdb.yaml`.

## 4. Wire network policy

`infrastructure/base/network-policies.yaml` default-denies all ingress and
egress in the namespace; every cross-pod path must be explicitly allowed.
Add `NetworkPolicy` pairs (ingress on the target, egress on the source) for
whatever the new workload needs to reach (Traefik routing in, DB or Keycloak
out, etc.), following the existing `allow-server-to-db` /
`allow-server-to-db-egress` pairs as a template. If Traefik should route to
it, also add it to the `app: In [...]` list in `allow-traefik-to-apps` and
`allow-traefik-egress`.

## 5. Add ingress routing (only if externally reachable)

Add a path rule to `infrastructure/base/networking/main-ingress.yaml`
(IngressRoute) if the workload needs to be reachable through the shared
domain, mirroring the existing `/api` (server) or `/` (web) rules.

## 6. Validate

```bash
make validate   # kustomize build for every overlay
make lint        # kubeconform schema validation
```

Both must pass before committing — they're enforced in CI
(`.github/workflows/validate.yaml`).
