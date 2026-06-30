<!--

This source file is part of the Stanford Spezi open source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Study Platform Infrastructure

GitOps infrastructure for the Spezi Study Platform, managing deployment of the [Server](https://github.com/StanfordSpezi/SpeziStudyPlatform-Server) and [Web](https://github.com/StanfordSpezi/SpeziStudyPlatform-Web) applications alongside supporting services (Keycloak, PostgreSQL, Traefik) across local and production environments. Built with ArgoCD, Kustomize, Helm, and OpenTofu.

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

For running backing services (PostgreSQL, Keycloak) without Kubernetes, see the [Docker setup guide](docker/README.md). This is the recommended approach when developing the [Server](https://github.com/StanfordSpezi/SpeziStudyPlatform-Server) or [Web](https://github.com/StanfordSpezi/SpeziStudyPlatform-Web) repositories locally.

## Using This as a Starter Template

This repo is also a working reference for standing up backend/infra (ArgoCD + Kustomize + Helm + OpenTofu, with Postgres, Keycloak, and Traefik wired together) for a new Spezi-based study platform.

To fork it for a new app:

1. Fork/copy the repo.
2. Run `tools/rename-project.sh <new-app-name> [--registry-org <org>] [--repo-url <url>] [--domain <domain>]` to rewrite the ~240 hardcoded `spezistudyplatform` identifiers (namespace, ConfigMaps, Secrets, Keycloak realm, GCP project/cluster names, image refs) to your app name in one pass. It prints a dry-run-able file list and a list of manual follow-ups (README prose, CONTRIBUTORS.md, etc.) it intentionally leaves alone.
3. Run `make validate && make lint` to confirm the renamed overlays still build.
4. Use the `spezi-new-app` skill (`.claude/skills/spezi-new-app/`, for Claude Code users) to add additional backend/frontend workloads beyond the included server + web pattern.

## Contributing

We welcome contributions! Please read our [contributing guidelines](https://github.com/StanfordSpezi/.github/blob/main/CONTRIBUTING.md) for more information on how to get started.

## License

This project is licensed under the MIT License. See [Licenses](https://github.com/StanfordSpezi/SpeziStudyPlatform-Infrastructure/tree/main/LICENSES) for more information.

## Contributors

This project is developed as part of the Stanford Byers Center for Biodesign at Stanford University.
See [CONTRIBUTORS.md](https://github.com/StanfordSpezi/SpeziStudyPlatform-Infrastructure/tree/main/CONTRIBUTORS.md) for a full list of all contributors.

![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-light.png#gh-light-mode-only)
![Stanford Byers Center for Biodesign Logo](https://raw.githubusercontent.com/StanfordBDHG/.github/main/assets/biodesign-footer-dark.png#gh-dark-mode-only)
