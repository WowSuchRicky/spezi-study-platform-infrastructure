#!/bin/bash
set -e

# --- Configuration ---
KIND_CLUSTER_NAME="spezi-study-platform"
# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOOTSTRAP_DIR="$SCRIPT_DIR/local-dev/bootstrap"
# We need a Tanka env to generate the apps. Let's reuse the one I made before.
# I need to recreate it.
BOOTSTRAP_ENV="environments/argocd-bootstrap"

# --- Helper Functions ---
info() {
    echo "INFO: $1"
}

# 1. Create KIND cluster
info "Creating KIND cluster '$KIND_CLUSTER_NAME'..."
if ! command -v kind &> /dev/null; then
    info "kind is not installed. Please install it first."
    exit 1
fi
if ! kind get clusters | grep -q "$KIND_CLUSTER_NAME"; then
  kind create cluster --name "$KIND_CLUSTER_NAME" --config="$SCRIPT_DIR/local-dev/kind-config.yaml"
else
  info "KIND cluster '$KIND_CLUSTER_NAME' already exists."
fi
info "KIND cluster is ready."

# 2. Install Argo CD
info "Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
info "Giving resources a moment to be created..."
sleep 5
info "Waiting for Argo CD pods to be ready..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s
info "Argo CD is ready."

# 3. Install and Register Tanka Custom Tool Plugin
info "Installing Tanka custom tools..."
kubectl patch deployment argocd-repo-server -n argocd --patch-file "$SCRIPT_DIR/local-dev/argocd-tool-patch.yaml"
info "Waiting for repo-server to be patched with custom tools..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=120s

info "Registering Tanka plugin..."
kubectl apply -f "$SCRIPT_DIR/local-dev/argocd-plugin-cm.yaml"
# We need to restart the repo-server for it to pick up the new plugin config
info "Restarting repo-server to apply plugin..."
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=120s
info "Tanka plugin is ready."

# 4. Bootstrap Argo CD Applications
info "Bootstrapping Argo CD applications..."
if ! command -v tk &> /dev/null; then
    info "Tanka (tk) is not installed. Please install it to continue."
    exit 1
fi
if ! command -v jb &> /dev/null; then
    info "Jsonnet Bundler (jb) is not installed. Please install it to continue."
    exit 1
fi

info "Installing Jsonnet dependencies..."
jb install

info "Exporting Argo CD application manifests from Tanka..."
# I deleted the bootstrap env before. I need to recreate it to use tk export.
# Or, I can just apply the argocd-apps.libsonnet directly if I construct a valid entrypoint.
# The user wants to use Tanka. So I need the bootstrap env.
# I will create it again. It was deleted in a cleanup step.
mkdir -p "$SCRIPT_DIR/environments/argocd-bootstrap"
cat <<EOF > "$SCRIPT_DIR/environments/argocd-bootstrap/spec.json"
{
  "apiVersion": "tanka.dev/v1alpha1",
  "kind": "Environment",
  "metadata": { "name": "argocd-bootstrap" },
  "spec": {
    "apiServer": "https://kubernetes.default.svc",
    "namespace": "argocd"
  }
}
EOF
cat <<EOF > "$SCRIPT_DIR/environments/argocd-bootstrap/main.jsonnet"
local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';
local config = { namespace: 'argocd' };
argocdApps.withConfig(config)
EOF

rm -rf "$BOOTSTRAP_DIR"
tk export "$BOOTSTRAP_DIR" "$BOOTSTRAP_ENV"

info "Applying Argo CD application manifests..."
find "$BOOTSTRAP_DIR" -type f -name "*.yaml" -exec kubectl apply -f {} \;

info "Setup complete!"
info "Argo CD is now configured to manage the local-dev environment."
info "Applications will be deployed in waves. Monitor progress in the Argo CD UI."
info "To access the Argo CD UI:"
echo "Argo CD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo ""
info "To port-forward the UI, run:"
info "kubectl port-forward svc/argocd-server -n argocd 8080:443"
