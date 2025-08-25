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

trap 'cleanup' EXIT

cleanup() {
    info "Cleaning up..."
    if [ -n "$PORT_FORWARD_PID" ] && ps -p $PORT_FORWARD_PID > /dev/null; then
        kill $PORT_FORWARD_PID
    fi
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
kubectl apply -f "$SCRIPT_DIR/config/argocd/argocd-tanka-cmp-configmap.yaml"
kubectl patch deployment argocd-repo-server -n argocd --patch-file "$SCRIPT_DIR/config/argocd/repo-server-patch.yaml"
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
    targetRevision: convert-prod-env
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

# 5. Wait for ArgoCD to sync and deploy applications
info "Waiting for ArgoCD root application to sync..."

# Wait for root application to be synced
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get application root -n argocd >/dev/null 2>&1; then
        app_status=$(kubectl get application root -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        health_status=$(kubectl get application root -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        info "Root application sync status: $app_status, health: $health_status"
        
        if [ "$app_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            info "Root application is synced and healthy!"
            break
        fi
    fi
    info "Waiting for root application to sync... (attempt $((attempt+1))/$max_attempts)"
    sleep 10
    ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
    info "Warning: Root application may not be fully synced. Proceeding anyway..."
fi

info "Waiting for wave 0 applications to be deployed..."
# Wait specifically for namespace application to be synced
max_attempts=20
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get application local-dev-namespace -n argocd >/dev/null 2>&1; then
        app_status=$(kubectl get application local-dev-namespace -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        info "Namespace application sync status: $app_status"
        
        if [ "$app_status" = "Synced" ]; then
            info "Namespace application is synced!"
            break
        fi
    fi
    info "Waiting for namespace application to be created and synced... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
done

info "Waiting for spezistudyplatform namespace to be created..."
# Wait for namespace to exist with retry logic
max_attempts=20
attempt=0
while ! kubectl get namespace spezistudyplatform >/dev/null 2>&1; do
    info "Waiting for namespace to be created... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
    if [ $attempt -eq $max_attempts ]; then
        info "Error: spezistudyplatform namespace not found after waiting. Check ArgoCD sync status."
        kubectl get applications -n argocd
        exit 1
    fi
done
info "Namespace spezistudyplatform found!"

info "Waiting for Keycloak statefulset to be available..."
# Wait for keycloak to exist with retry logic
max_attempts=20
attempt=0
while ! kubectl get statefulset keycloak -n spezistudyplatform >/dev/null 2>&1; do
    info "Waiting for Keycloak statefulset to be created... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
    if [ $attempt -eq $max_attempts ]; then
        info "Error: Keycloak statefulset not found after waiting. Check ArgoCD sync status."
        exit 1
    fi
done
info "Keycloak statefulset found!"
kubectl rollout status statefulset/keycloak -n spezistudyplatform --timeout=600s

info "Waiting for Keycloak pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n spezistudyplatform --timeout=300s

# Bootstrap Keycloak realm and OAuth2 proxy client
info "Bootstrapping Keycloak realm and OAuth2 proxy configuration..."

# Port forward to access Keycloak
kubectl port-forward -n spezistudyplatform svc/keycloak 8081:80 &
PORT_FORWARD_PID=$!
info "Waiting for port-forward to be ready..."
sleep 5

info "Waiting for Keycloak to be fully ready..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl --output /dev/null --silent --head --fail http://localhost:8081/auth/; then
        info "Keycloak is ready!"
        break
    fi
    info "Waiting for Keycloak to be ready... (attempt $((attempt+1))/$max_attempts)"
    sleep 10
    ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
    info "Error: Keycloak is not ready after waiting."
    exit 1
fi

# Run Tofu bootstrap
cd "$SCRIPT_DIR/tofu/keycloak-bootstrap/tf"
if ! command -v tofu &> /dev/null; then
    info "Warning: tofu is not installed. Skipping Keycloak bootstrap."
    info "Please install tofu and run manually:"
    info "cd tofu/keycloak-bootstrap/tf && tofu init && tofu apply"
else
    info "Running Keycloak bootstrap with Tofu..."
    tofu init
    tofu apply -var="keycloak_url=http://localhost:8081/auth" -var="keycloak_password=admin123!" -auto-approve
    info "Keycloak bootstrap completed successfully!"
fi

cd "$SCRIPT_DIR"

# 6. Final setup message

info "Setup complete!"
info "Argo CD is now configured to manage the local-dev environment."
info "Applications will be deployed in waves. Monitor progress in the Argo CD UI."
info "To access the Argo CD UI:"
echo "Argo CD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo ""
info "To port-forward the UI, run:"
info "kubectl port-forward svc/argocd-server -n argocd 8080:443"
