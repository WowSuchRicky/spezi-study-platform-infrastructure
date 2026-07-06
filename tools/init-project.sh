#!/usr/bin/env bash
#
# This source file is part of the Stanford Spezi open source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

# Renders this template repo into a working backend/infra setup for a new
# Spezi-based study platform by replacing the placeholder tokens checked
# into the repo (app-name-placeholder, app-name-pascal-placeholder,
# app-name-kebab-placeholder, registry-org-placeholder, repo-url-placeholder,
# domain-placeholder) with real values. Run with --help for full usage.
#
# This repo does NOT work as checked in: `make validate`/`make lint` will
# pass (the placeholders are valid YAML), but `make dev` / `make
# prod-bootstrap` refuse to run until every placeholder has been rendered --
# see the guard in tools/setup.py.
#
# Note: domain-placeholder (rendered here) is unrelated to the
# DOMAIN_PLACEHOLDER token used internally by the dev/prod Kustomize
# overlays themselves -- that one is a separate, pre-existing mechanism for
# the per-environment domain override and is not touched by this script.

set -euo pipefail

usage() {
    cat <<'EOF'
Renders this template repo into a working backend/infra setup by replacing
the placeholder tokens checked into the repo with real values.

Usage:
  tools/init-project.sh <app-name> [options]

Arguments:
  <app-name>               New app name in kebab-case, e.g. "my-research-app".

Options:
  --registry-org <org>     Container registry org/user
  --repo-url <url>         This repo's own git URL (your fork, not the template)
  --domain <domain>        Production domain
  --dry-run                Print matching files without modifying anything

Any option you omit leaves that placeholder token in place. Run again later
to fill in the rest; this script is idempotent.

Example:
  tools/init-project.sh my-research-app \
    --registry-org my-org \
    --repo-url https://github.com/my-org/my-research-app-infra.git \
    --domain platform.my-research.edu
EOF
    exit 1
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

NEW_NAME="$1"
shift

if [[ ! "$NEW_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Error: <app-name> must be kebab-case (lowercase letters, digits, hyphens), e.g. 'my-research-app'." >&2
    exit 1
fi

REGISTRY_ORG=""
REPO_URL=""
DOMAIN=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry-org)
            [[ $# -lt 2 ]] && { echo "Error: --registry-org requires a value" >&2; exit 1; }
            REGISTRY_ORG="$2"; shift 2 ;;
        --repo-url)
            [[ $# -lt 2 ]] && { echo "Error: --repo-url requires a value" >&2; exit 1; }
            REPO_URL="$2"; shift 2 ;;
        --domain)
            [[ $# -lt 2 ]] && { echo "Error: --domain requires a value" >&2; exit 1; }
            DOMAIN="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEBAB="$NEW_NAME"
LOWER="${NEW_NAME//-/}"
PASCAL="$(python3 -c "import sys; print(''.join(w.capitalize() for w in sys.argv[1].split('-')))" "$NEW_NAME")"

echo "App name: $NEW_NAME"
echo "  app-name-pascal-placeholder -> $PASCAL"
echo "  app-name-placeholder        -> $LOWER"
echo "  app-name-kebab-placeholder  -> $KEBAB"
[[ -n "$REGISTRY_ORG" ]] && echo "  registry-org-placeholder    -> $REGISTRY_ORG"
[[ -n "$REPO_URL" ]] && echo "  repo-url-placeholder        -> $REPO_URL"
[[ -n "$DOMAIN" ]] && echo "  domain-placeholder           -> $DOMAIN"
echo

# Text files under version control, excluding this script and
# tools/setup.py -- both reference the placeholder names literally as part
# of their own implementation (usage text / the rendered-check regex), not
# as unrendered template content.
FILES=()
while IFS= read -r line; do
    FILES+=("$line")
done < <(git -C "$ROOT" ls-files | grep -vE '^tools/(init-project\.sh|setup\.py)$')

PLACEHOLDER_RE='app-name-pascal-placeholder|app-name-kebab-placeholder|app-name-placeholder|registry-org-placeholder|repo-url-placeholder|domain-placeholder'

MATCHED=()
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    grep -Iq . "$f" 2>/dev/null || continue # skip binaries
    grep -qE "$PLACEHOLDER_RE" "$f" 2>/dev/null && MATCHED+=("$f")
done

echo "Files with placeholders (${#MATCHED[@]}):"
printf '  %s\n' "${MATCHED[@]}"
echo

if $DRY_RUN; then
    echo "Dry run: no files modified."
    exit 0
fi

for f in "${MATCHED[@]}"; do
    tmp="$(mktemp)"
    sed \
        -e "s/app-name-pascal-placeholder/${PASCAL}/g" \
        -e "s/app-name-kebab-placeholder/${KEBAB}/g" \
        -e "s/app-name-placeholder/${LOWER}/g" \
        $([[ -n "$REGISTRY_ORG" ]] && echo "-e s#registry-org-placeholder#${REGISTRY_ORG}#g") \
        $([[ -n "$REPO_URL" ]] && echo "-e s#repo-url-placeholder#${REPO_URL}#g") \
        $([[ -n "$DOMAIN" ]] && echo "-e s#domain-placeholder#${DOMAIN}#g") \
        "$f" > "$tmp" && mv "$tmp" "$f"
done

echo "Done."
echo

REMAINING=()
for f in "${MATCHED[@]}"; do
    grep -qE "$PLACEHOLDER_RE" "$f" 2>/dev/null && REMAINING+=("$f")
done

if [[ ${#REMAINING[@]} -gt 0 ]]; then
    echo "Still unrendered (re-run with the matching flag when ready):"
    for f in "${REMAINING[@]}"; do
        echo "  $f:"
        grep -oE "$PLACEHOLDER_RE" "$f" | sort -u | sed 's/^/    /'
    done
    echo
    echo "make dev / tools/setup.py will refuse to run until these are gone."
    echo
fi

cat <<'EOF'
Manual follow-ups (not auto-rewritten, by design):
  - README.md / docker/README.md / AGENTS.md prose
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
