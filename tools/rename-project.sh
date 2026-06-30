#!/usr/bin/env bash
#
# This source file is part of the Stanford Spezi open source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

# Forks this repository into a starter template for a new Spezi-based study
# platform by rewriting every "spezistudyplatform" identifier (namespace,
# ConfigMaps, Secrets, Keycloak realm/roles, GCP project/cluster names, image
# refs) to a new app name in one pass.
#
# Usage:
#   tools/rename-project.sh <new-name> [options]
#
# Arguments:
#   <new-name>              New app name in kebab-case, e.g. "my-research-app".
#                            Used to derive:
#                              - PascalCase  (MyResearchApp)   replaces SpeziStudyPlatform
#                              - lowercase   (myresearchapp)   replaces spezistudyplatform
#                              - kebab-case  (my-research-app) replaces spezi-study-platform
#
# Options:
#   --registry-org <org>    Replace ghcr.io/stanfordspezi/ with ghcr.io/<org>/
#   --repo-url <url>        Replace the ArgoCD repoURL (argocd-apps/*) with <url>
#   --domain <domain>       Replace the prod domain platform.spezi.stanford.edu
#   --dry-run               Print matching files without modifying anything
#
# Example:
#   tools/rename-project.sh my-research-app \
#     --registry-org my-org \
#     --repo-url https://github.com/my-org/my-research-app-infrastructure.git \
#     --domain platform.my-research.edu
#
# Run this once right after forking, review the resulting `git diff`, then
# commit. It does not touch the Stanford Spezi SPDX license headers or
# CONTRIBUTORS.md, and it does not rewrite human-readable prose (README
# titles, docs) -- update those by hand.

set -euo pipefail

usage() {
    grep '^#' "$0" | sed -e 's/^#//' -e 's/^ //' | sed -n '/^Forks/,/^commit\.$/p'
    exit 1
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

NEW_NAME="$1"
shift

if [[ ! "$NEW_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Error: <new-name> must be kebab-case (lowercase letters, digits, hyphens), e.g. 'my-research-app'." >&2
    exit 1
fi

REGISTRY_ORG=""
REPO_URL=""
DOMAIN=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry-org) REGISTRY_ORG="$2"; shift 2 ;;
        --repo-url) REPO_URL="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEBAB="$NEW_NAME"
LOWER="${NEW_NAME//-/}"
PASCAL="$(echo "$NEW_NAME" | sed -E 's/(^|-)([a-z])/\U\2/g')"

OLD_REPO_URL="https://github.com/StanfordSpezi/spezi-study-platform-infrastructure.git"
OLD_DOMAIN="platform.spezi.stanford.edu"
OLD_REGISTRY="ghcr.io/stanfordspezi/"

echo "New app name: $NEW_NAME"
echo "  PascalCase -> $PASCAL   (replaces SpeziStudyPlatform)"
echo "  lowercase  -> $LOWER    (replaces spezistudyplatform)"
echo "  kebab-case -> $KEBAB    (replaces spezi-study-platform)"
[[ -n "$REGISTRY_ORG" ]] && echo "  registry   -> ghcr.io/$REGISTRY_ORG/ (replaces $OLD_REGISTRY)"
[[ -n "$REPO_URL" ]] && echo "  repo URL   -> $REPO_URL"
[[ -n "$DOMAIN" ]] && echo "  domain     -> $DOMAIN"
echo

# Text files under version control, excluding this script itself so reruns
# stay idempotent against its own usage text.
mapfile -t FILES < <(git -C "$ROOT" ls-files | grep -v '^tools/rename-project\.sh$')

MATCHED=()
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    grep -Iq . "$f" 2>/dev/null || continue # skip binaries
    if grep -qE "spezistudyplatform|SpeziStudyPlatform|spezi-study-platform" "$f" 2>/dev/null \
        || { [[ -n "$REGISTRY_ORG" ]] && grep -qF "$OLD_REGISTRY" "$f" 2>/dev/null; } \
        || { [[ -n "$REPO_URL" ]] && grep -qF "$OLD_REPO_URL" "$f" 2>/dev/null; } \
        || { [[ -n "$DOMAIN" ]] && grep -qF "$OLD_DOMAIN" "$f" 2>/dev/null; }; then
        MATCHED+=("$f")
    fi
done

echo "Files to update (${#MATCHED[@]}):"
printf '  %s\n' "${MATCHED[@]}"
echo

if $DRY_RUN; then
    echo "Dry run: no files modified."
    exit 0
fi

for f in "${MATCHED[@]}"; do
    sed -i \
        -e "s#${OLD_REPO_URL}#${REPO_URL:-$OLD_REPO_URL}#g" \
        -e "s#${OLD_REGISTRY}#ghcr.io/${REGISTRY_ORG:-stanfordspezi}/#g" \
        -e "s#${OLD_DOMAIN}#${DOMAIN:-$OLD_DOMAIN}#g" \
        -e "s/SpeziStudyPlatform/${PASCAL}/g" \
        -e "s/spezistudyplatform/${LOWER}/g" \
        -e "s/spezi-study-platform/${KEBAB}/g" \
        "$f"
done

echo "Done. Review the diff, then handle the manual follow-ups below:"
cat <<EOF

Manual follow-ups (not auto-rewritten, by design):
  - README.md / docker/README.md / AGENTS.md prose ("Spezi Study Platform" with spaces)
  - CONTRIBUTORS.md and links to the StanfordSpezi GitHub org
  - SPDX license headers (left as-is; they describe the upstream Spezi project, not your app)
  - terraform.tfvars (not version controlled) and any local .env files
  - The Server/Web application repos themselves (this repo only deploys them)
  - GitHub repo name / branch protections / CI secrets for the new remote

Next steps:
  git diff --stat
  make validate   # confirm all Kustomize overlays still build
  make lint
EOF
