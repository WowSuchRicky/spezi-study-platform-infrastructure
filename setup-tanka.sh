#!/bin/bash
set -e

# --- Configuration ---
KIND_CLUSTER_NAME="spezi-study-platform"
# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

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

# 3. Install Tanka CMP Plugin
info "Installing Tanka Config Management Plugin..."
kubectl apply -f "$SCRIPT_DIR/kube/argocd/argocd-tanka-cmp-configmap.yaml"
kubectl patch deployment argocd-repo-server -n argocd --patch-file "$SCRIPT_DIR/kube/argocd/repo-server-patch.yaml"
info "Waiting for ArgoCD repo server to restart with Tanka plugin..."
kubectl rollout status deployment argocd-repo-server -n argocd
info "Tanka CMP plugin is ready."

# 4. Bootstrap Argo CD Root Application
info "Bootstrapping Argo CD Root Application..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git
    path: environments/argocd-bootstrap
    targetRevision: jsonnet-working
    directory:
      exclude: spec.json
      jsonnet: {}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - ServerSideApply=true
EOF

info "Setup complete!"
info "Argo CD is now configured to manage the local-dev environment."
info "Applications will be deployed in waves. Monitor progress in the Argo CD UI."
info "To access the Argo CD UI:"
echo "Argo CD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo ""
info "To port-forward the UI, run:"
info "kubectl port-forward svc/argocd-server -n argocd 8080:443"
