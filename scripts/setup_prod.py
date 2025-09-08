#!/usr/bin/env python3
"""
Modular setup/bootstrapping CLI for the project.

This script provides subcommands that mirror stages from the original
`setup-prod.sh` but in a modular, safer way. It intentionally delegates
to the existing CLIs (gcloud, ansible-playbook, kubectl, tofu/terraform)
to avoid reimplementing behavior.

Usage examples:
  ./scripts/setup_prod.py --help
  ./scripts/setup_prod.py gcp-setup
  ./scripts/setup_prod.py keycloak-bootstrap --yes
  ./scripts/setup_prod.py full --dry-run

Notes:
 - The script will try to read basic defaults from `setup-prod.sh` located
   in the repository root (simple VAR="value" lines). It does not execute
   that script.
 - It does not require new Python dependencies; uses stdlib only.
"""

import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SETUP_SH = REPO_ROOT / 'setup-prod.sh'


def parse_defaults_from_setup_sh(path: Path):
    """Parse a few simple VAR="value" defaults from setup-prod.sh.

    Returns a dict with keys for any found vars.
    """
    defaults = {}
    if not path.exists():
        return defaults
    pattern = re.compile(r'^(?P<key>[A-Z0-9_]+)="(?P<val>.*)"')
    with path.open('r') as f:
        for line in f:
            m = pattern.match(line.strip())
            if m:
                defaults[m.group('key')] = m.group('val')
    return defaults


def run(cmd, dry_run=False, check=True, env=None):
    print(f"RUN: {cmd}")
    if dry_run:
        return 0
    if isinstance(cmd, str):
        args = shlex.split(cmd)
    else:
        args = cmd
    return subprocess.run(args, check=check, env=env).returncode


def ensure_installed(tool):
    if shutil.which(tool) is None:
        print(f"Required tool not found in PATH: {tool}")
        return False
    return True


def gcp_setup(args, defaults):
    # checks
    for t in ('gcloud', 'gsutil'):
        if not ensure_installed(t):
            raise SystemExit(1)

    project = args.project or defaults.get('GCP_PROJECT_ID')
    if not project:
        print("GCP project not provided and not found in setup-prod.sh. Use --project.")
        raise SystemExit(2)

    print(f"Setting gcloud project: {project}")
    run(f"gcloud config set project {project}", dry_run=args.dry_run)

    apis = [
        'secretmanager.googleapis.com',
        'iamcredentials.googleapis.com',
        'cloudresourcemanager.googleapis.com',
        'iap.googleapis.com',
    ]
    for api in apis:
        run(f"gcloud services enable {api} --project={project}", dry_run=args.dry_run)

    # service account key creation is left to the original script logic;
    # we expose the same file path as default
    sa_email = f"spezistudyplatform-dev-svc@{project}.iam.gserviceaccount.com"
    cred_path = REPO_ROOT / 'gcp-service-account-key.json'
    if cred_path.exists():
        print(f"Credentials file already exists: {cred_path}")
    else:
        if args.dry_run:
            print(f"Would create service account key for {sa_email} -> {cred_path}")
        else:
            run(f"gcloud iam service-accounts keys create {cred_path} --iam-account={sa_email}")

    print("GCP setup finished (partial). Review the original script for additional checks.")


def provision_gke(args, defaults):
    # delegate to ansible playbook as before
    if not ensure_installed('ansible-playbook'):
        raise SystemExit(1)
    cwd = REPO_ROOT
    cmd = f"ansible-playbook ansible/provision-gke.yaml"
    run(cmd, dry_run=args.dry_run, check=not args.ignore_errors)


def verify_kubectl(args, defaults):
    if not ensure_installed('kubectl'):
        raise SystemExit(1)
    run('kubectl cluster-info', dry_run=args.dry_run)


def install_argocd(args, defaults):
    if not ensure_installed('kubectl'):
        raise SystemExit(1)
    run('kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -', dry_run=args.dry_run)
    run('kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.1.4/manifests/install.yaml', dry_run=args.dry_run)
    # apply custom config
    cfg = REPO_ROOT / 'config' / 'argocd' / 'argocd-cm-config.yaml'
    if cfg.exists():
        run(f'kubectl apply -f "{cfg}"', dry_run=args.dry_run)
    else:
        print(f"Warning: {cfg} not found; skipping custom argocd config")


def tanka_plugin(args, defaults):
    if not ensure_installed('kubectl'):
        raise SystemExit(1)
    cfg = REPO_ROOT / 'config' / 'argocd' / 'argocd-tanka-cmp-configmap.yaml'
    patch = REPO_ROOT / 'config' / 'argocd' / 'repo-server-patch.yaml'
    if cfg.exists():
        run(f'kubectl apply -f "{cfg}"', dry_run=args.dry_run)
    if patch.exists():
        run(f'kubectl patch deployment argocd-repo-server -n argocd --patch-file "{patch}"', dry_run=args.dry_run)


def bootstrap_argocd_app(args, defaults):
    # create root-prod application similarly to the bash script
    if not ensure_installed('kubectl'):
        raise SystemExit(1)
    repo = 'https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git'
    branch = subprocess.getoutput('git rev-parse --abbrev-ref HEAD')
    yaml = f"""
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: {repo}
    path: environments/prod-bootstrap
    targetRevision: {branch}
    directory:
      exclude: spec.json
      jsonnet:
        tlas:
        - name: gitBranch
          value: {branch}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - ServerSideApply=true
"""
    proc = subprocess.Popen(['kubectl', 'apply', '-f', '-'], stdin=subprocess.PIPE)
    if args.dry_run:
        print('Would apply Application YAML:')
        print(yaml)
        return
    proc.communicate(yaml.encode())
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def keycloak_bootstrap(args, defaults):
    # Run tofu/terraform apply in tofu/keycloak-bootstrap/tf
    tf_dir = REPO_ROOT / 'tofu' / 'keycloak-bootstrap' / 'tf'
    if not tf_dir.exists():
        print(f"Keycloak terraform directory not found: {tf_dir}")
        raise SystemExit(1)

    tfcmd = 'tofu' if shutil.which('tofu') else 'terraform'
    vars = []
    # basic vars as in the shell script
    prod_domain = defaults.get('PRODUCTION_DOMAIN')
    gcp_project = defaults.get('GCP_PROJECT_ID')
    if not prod_domain or not gcp_project:
        print('Missing PRODUCTION_DOMAIN or GCP_PROJECT_ID in defaults; falling back to runtime values or prompting')

    cmd_init = f'cd "{tf_dir}" && {tfcmd} init'
    cmd_apply = f'cd "{tf_dir}" && {tfcmd} apply -var="keycloak_url=http://localhost:8081/auth" -var="keycloak_password=admin123!" -var="frontend_url=https://{prod_domain or ""}" -var="gcp_project_id={gcp_project or ""}" -auto-approve'
    run(cmd_init, dry_run=args.dry_run)
    run(cmd_apply, dry_run=args.dry_run)


def full_flow(args, defaults):
    steps = [
        ('gcp setup', gcp_setup),
        ('provision gke', provision_gke),
        ('verify kubectl', verify_kubectl),
        ('install argocd', install_argocd),
        ('tanka plugin', tanka_plugin),
        ('bootstrap argocd app', bootstrap_argocd_app),
        ('wait & keycloak bootstrap', keycloak_bootstrap),
    ]
    for name, fn in steps:
        print(f"--- {name} ---")
        fn(args, defaults)


def main():
    defaults = parse_defaults_from_setup_sh(SETUP_SH)

    parser = argparse.ArgumentParser(description='Modular bootstrap CLI')
    parser.add_argument('--dry-run', action='store_true', help='Print commands without executing')
    parser.add_argument('--yes', action='store_true', help='Assume yes for confirmations')
    subparsers = parser.add_subparsers(dest='cmd')

    p = subparsers.add_parser('gcp-setup', help='Enable APIs and create service account key')
    p.add_argument('--project', help='GCP project id')

    p = subparsers.add_parser('provision-gke', help='Run ansible playbook to provision GKE')

    p = subparsers.add_parser('verify-kubectl', help='Run kubectl cluster-info')

    p = subparsers.add_parser('install-argocd', help='Install ArgoCD into cluster')

    p = subparsers.add_parser('tanka-plugin', help='Install Tanka plugin config for ArgoCD')

    p = subparsers.add_parser('bootstrap-argocd-app', help='Create root-prod ArgoCD application')

    p = subparsers.add_parser('keycloak-bootstrap', help='Run terraform/tofu Keycloak bootstrap')

    p = subparsers.add_parser('full', help='Run full flow (safe defaults in order)')

    args = parser.parse_args()
    if args.cmd is None:
        parser.print_help()
        raise SystemExit(1)

    # set a simple args object that has dry_run and yes
    args.dry_run = getattr(args, 'dry_run', False)
    args.yes = getattr(args, 'yes', False)
    args.ignore_errors = False

    try:
        if args.cmd == 'gcp-setup':
            gcp_setup(args, defaults)
        elif args.cmd == 'provision-gke':
            provision_gke(args, defaults)
        elif args.cmd == 'verify-kubectl':
            verify_kubectl(args, defaults)
        elif args.cmd == 'install-argocd':
            install_argocd(args, defaults)
        elif args.cmd == 'tanka-plugin':
            tanka_plugin(args, defaults)
        elif args.cmd == 'bootstrap-argocd-app':
            bootstrap_argocd_app(args, defaults)
        elif args.cmd == 'keycloak-bootstrap':
            keycloak_bootstrap(args, defaults)
        elif args.cmd == 'full':
            full_flow(args, defaults)
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}")
        raise SystemExit(e.returncode)


if __name__ == '__main__':
    main()
