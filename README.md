<!--

This source file is part of the Stanford Spezi open source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Study Platform Infrastructure Template

A GitOps infrastructure template for Spezi-based study platforms: ArgoCD, Kustomize, Helm, and OpenTofu, with a backend service, a frontend, PostgreSQL, Keycloak, and Traefik already wired together across local (KIND) and production (GKE) environments.

**This repo does not work as checked in.** Every namespace, ConfigMap, Secret, Keycloak realm, GCP project/cluster name, and image reference is one of the placeholder tokens (`app-name-placeholder`, `app-name-pascal-placeholder`, `app-name-kebab-placeholder`, `registry-org-placeholder`, `repo-url-placeholder`, `domain-placeholder` — see [`infrastructure/base/namespace.yaml`](infrastructure/base/namespace.yaml) for an example). You render it into your own app before anything will deploy — `make dev` and `make prod-bootstrap` both refuse to run until you have.

## Step 0: Render the Template

```bash
tools/init-project.sh <your-app-name> \
  --registry-org <your-github-or-registry-org> \
  --repo-url <url-of-your-fork> \
  --domain <your-prod-domain>
```

This rewrites every placeholder in the repo to real values in one pass (dry-run with `--dry-run` first if you want to preview). Any flag you omit leaves that placeholder in place — useful if you want to try `make validate` locally before deciding on a registry or domain, but `make dev`/`make prod-bootstrap` will block until all of them are filled in. Run `tools/init-project.sh --help` for details, and see "Manual follow-ups" in its output for the handful of things (README prose, CONTRIBUTORS.md, your own Server/Web app repos) it intentionally doesn't touch.

Once rendered:

```bash
git diff --stat   # review what changed
make validate     # confirm all Kustomize overlays still build
make lint         # kubeconform schema validation
```

To scaffold an additional backend/frontend workload beyond the included server + web pattern, follow the `spezi-new-app` skill (`.claude/skills/spezi-new-app/`, for Claude Code users) or read it directly — it documents the base/dev/prod Kustomize + NetworkPolicy wiring this repo expects for every workload.

## Prerequisites

Install via [Homebrew](https://brew.sh/) or your preferred package manager:

| Tool                                               | Install                       | Purpose                    |
| -------------------------------------------------- | ----------------------------- | -------------------------- |
| [kind](https://kind.sigs.k8s.io/)                  | `brew install kind`           | Local Kubernetes clusters  |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `brew install kubernetes-cli` | Kubernetes CLI             |
| [helm](https://helm.sh/)                           | `brew install helm`           | Kubernetes package manager |
| [python3](https://www.python.org/)                 | `brew install python`         | Setup and test scripts     |
| [kubeconform](https://github.com/yannh/kubeconform) | `brew install kubeconform`    | Schema validation          |

## Quick Start

Once the template is rendered (Step 0 above):

```bash
make dev            # Create KIND cluster, bootstrap ArgoCD + all services
make dev-status     # Check sync progress
make argocd-password # Get ArgoCD admin password
```

To bootstrap from a feature branch:

```bash
git push -u origin HEAD
make dev BRANCH=my-feature
```

To start fresh:

```bash
make dev-down && make dev
```

Run `make help` to list all available targets, including production commands for OpenTofu and GKE.

### Dev Test Users

All dev users share the password `password123`:

| Username             | Role                     |
| -------------------- | ------------------------ |
| `leland@example.com` | Researcher, ArgoCD Admin |
| `jane@example.com`   | Researcher               |
| `alice@example.com`  | Participant              |

## Docker Development

For running backing services (PostgreSQL, Keycloak) without Kubernetes, see the [Docker setup guide](docker/README.md). This is the recommended approach when developing your own server/web applications locally. The template must be rendered first (Step 0) — `docker-compose.yml` and `.env.example` both contain the same placeholders.

## Contributing

We welcome contributions! Please read our [contributing guidelines](https://github.com/StanfordSpezi/.github/blob/main/CONTRIBUTING.md) for more information on how to get started.

## License

This project is licensed under the MIT License. See [Licenses](LICENSES) for more information.

## Contributors

This template originates from the Stanford Byers Center for Biodesign at Stanford University.
See [CONTRIBUTORS.md](CONTRIBUTORS.md) for a full list of all contributors.

![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-light.png#gh-light-mode-only)
![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-dark.png#gh-dark-mode-only)
