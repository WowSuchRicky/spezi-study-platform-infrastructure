#!/bin/bash
set -e

# --- Configuration ---
KIND_CLUSTER_NAME="spezi-study-platform"
# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOOTSTRAP_DIR="$SCRIPT_DIR/local-dev/bootstrap"
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
info "Waiting for Argo CD pods to be ready..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s
info "Argo CD is ready."

# 3. Install Tanka plugin for Argo CD
info "Installing Tanka plugin..."
kubectl apply -f "$SCRIPT_DIR/local-dev/argocd-tanka-plugin.yaml"
info "Patching Argo CD repo server to enable Tanka plugin..."
kubectl patch deployment argocd-repo-server -n argocd --patch-file "$SCRIPT_DIR/local-dev/argocd-tanka-plugin-patch.yaml"
info "Waiting for patched repo server to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=120s
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
rm -rf "$BOOTSTRAP_DIR"
tk export "$BOOTSTRAP_DIR" "$BOOTSTRAP_ENV"

info "Applying Argo CD application manifests..."
kubectl apply -f "$BOOTSTRAP_DIR"

info "Setup complete!"
info "Argo CD is now configured to manage the local-dev environment."
info "Applications will be deployed in waves. Monitor progress in the Argo CD UI."
info "To access the Argo CD UI:"
info "1. Get the admin password:"
info "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
info "2. Port-forward the UI:"
info "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
