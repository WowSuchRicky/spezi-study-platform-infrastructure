#!/bin/bash
set -e

# --- Configuration ---
# TODO: eventually get this from a more centralized config location or from GKE directly
GKE_CLUSTER_NAME="spezistudyplatform-dev-gke"
GCP_PROJECT_ID="spezistudyplatform-dev"
GCP_ZONE="us-west1-c"
PRODUCTION_DOMAIN="platform.spezi.stanford.edu"
STATIC_IP="34.168.131.83"

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- Helper Functions ---
info() {
    echo "INFO: $1"
}

error() {
    echo "ERROR: $1"
    exit 1
}

trap 'cleanup' EXIT

cleanup() {
    info "Cleaning up..."
    if [ -n "$PORT_FORWARD_PID" ] && ps -p $PORT_FORWARD_PID > /dev/null; then
        kill $PORT_FORWARD_PID
    fi
}

# --- Prerequisites Check ---
info "Checking prerequisites..."

# Check required tools
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install it first."
fi

if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed. Please install it first."
fi

if ! command -v ansible-playbook &> /dev/null; then
    error "ansible is not installed. Please install it first."
fi

if ! command -v tofu &> /dev/null && ! command -v terraform &> /dev/null; then
    error "tofu or terraform is not installed. Please install one of them first."
fi

# --- 1. GCP Authentication & Setup ---
info "Setting up GCP authentication and configuration..."

# Verify gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    info "No active gcloud authentication found. Please authenticate:"
    gcloud auth login
fi

# Set project
info "Setting GCP project to $GCP_PROJECT_ID"
gcloud config set project "$GCP_PROJECT_ID"

# Enable required APIs
info "Enabling required GCP APIs..."
gcloud services enable secretmanager.googleapis.com --project="$GCP_PROJECT_ID"
gcloud services enable iamcredentials.googleapis.com --project="$GCP_PROJECT_ID"
gcloud services enable cloudresourcemanager.googleapis.com --project="$GCP_PROJECT_ID"
gcloud services enable iap.googleapis.com --project="$GCP_PROJECT_ID"

# Create or verify service account key
SERVICE_ACCOUNT_EMAIL="spezistudyplatform-dev-svc@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
CREDENTIALS_FILE="$SCRIPT_DIR/gcp-service-account-key.json"

info "Setting up service account key for: $SERVICE_ACCOUNT_EMAIL"

# Create service account key if credentials file doesn't exist
if [ ! -f "$CREDENTIALS_FILE" ]; then
    info "Creating new service account key and saving to $CREDENTIALS_FILE"
    gcloud iam service-accounts keys create "$CREDENTIALS_FILE" \
        --iam-account="$SERVICE_ACCOUNT_EMAIL"
    
    info "Service account key created successfully!"
else
    info "Service account key already exists at $CREDENTIALS_FILE"
fi

# Activate the service account
info "Activating service account for infrastructure operations..."
gcloud auth activate-service-account --key-file="$CREDENTIALS_FILE"

# Verify service account has necessary permissions and create bucket if needed
info "Verifying service account permissions and terraform state bucket..."
TERRAFORM_STATE_BUCKET="spezistudyplatform-tf-state-prod"

# Check if bucket exists, create if not
if ! gsutil ls "gs://$TERRAFORM_STATE_BUCKET" >/dev/null 2>&1; then
    info "Creating terraform state bucket: $TERRAFORM_STATE_BUCKET"
    gsutil mb -p "$GCP_PROJECT_ID" -l us-west1 "gs://$TERRAFORM_STATE_BUCKET"
    
    # Enable versioning for state bucket
    gsutil versioning set on "gs://$TERRAFORM_STATE_BUCKET"
else
    info "Terraform state bucket already exists: $TERRAFORM_STATE_BUCKET"
fi

# Verify service account has required roles
info "Verifying service account IAM roles..."
REQUIRED_ROLES=(
    "roles/storage.admin"
    "roles/container.admin"
    "roles/compute.admin"
    "roles/iam.serviceAccountUser"
    "roles/secretmanager.secretAccessor"
)

for role in "${REQUIRED_ROLES[@]}"; do
    if ! gcloud projects get-iam-policy "$GCP_PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="table(bindings.role)" \
        --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL AND bindings.role:$role" | grep -q "$role"; then
        
        info "Adding missing role $role to service account..."
        gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
            --role="$role"
    fi
done

# Update the credentials file path in ansible group_vars
info "Updating ansible group_vars with correct credentials path..."
if [ -f "$SCRIPT_DIR/ansible/group_vars/all.yaml" ]; then
    # Use sed to update the credentials file path
    sed -i.bak "s|gcp_credentials_file:.*|gcp_credentials_file: \"$CREDENTIALS_FILE\"|" "$SCRIPT_DIR/ansible/group_vars/all.yaml"
    info "Updated ansible/group_vars/all.yaml with credentials path: $CREDENTIALS_FILE"
fi

info "GCP setup complete."

# --- 2. Infrastructure Provisioning ---
info "Provisioning GKE infrastructure with Ansible..."

# Set environment variable for service account credentials
export GOOGLE_APPLICATION_CREDENTIALS="$CREDENTIALS_FILE"

# Run Ansible playbook to provision GKE cluster
cd "$SCRIPT_DIR"
ansible-playbook ansible/provision-gke.yaml

info "GKE cluster provisioned successfully."

# --- 3. Verify kubectl configuration ---
info "Verifying kubectl configuration for GKE cluster..."

# Verify cluster access (Ansible should have already configured kubectl)
kubectl cluster-info

info "kubectl configured for GKE cluster."

# --- 4. Install Argo CD ---
info "Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.1.4/manifests/install.yaml

# Apply custom ArgoCD configuration for resource ignoring
info "Applying ArgoCD configuration for PushSecret ignore rules..."
kubectl apply -f "$SCRIPT_DIR/config/argocd/argocd-cm-config.yaml"

info "Giving resources a moment to be created..."
sleep 5

info "Waiting for Argo CD pods to be ready..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=600s
info "Argo CD is ready."

# --- 5. Install Tanka CMP Plugin ---
info "Installing Tanka Config Management Plugin..."
kubectl apply -f "$SCRIPT_DIR/config/argocd/argocd-tanka-cmp-configmap.yaml"
kubectl patch deployment argocd-repo-server -n argocd --patch-file "$SCRIPT_DIR/config/argocd/repo-server-patch.yaml"

info "Waiting for ArgoCD repo server to restart with Tanka plugin..."
kubectl rollout status deployment argocd-repo-server -n argocd
info "Tanka CMP plugin is ready."

# --- 6. Bootstrap Argo CD Root Application ---
info "Bootstrapping Argo CD Root Application for production..."

# Delete existing application if it exists to ensure clean state
if kubectl get application root-prod -n argocd >/dev/null 2>&1; then
    info "Deleting existing root-prod application to recreate with correct configuration..."
    kubectl delete application root-prod -n argocd
    sleep 5
fi

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git
    path: environments/prod-bootstrap
    targetRevision: $(git rev-parse --abbrev-ref HEAD)
    directory:
      exclude: spec.json
      jsonnet:
        tlas:
        - name: gitBranch
          value: $(git rev-parse --abbrev-ref HEAD)
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

# --- 7. Wait for ArgoCD to sync and deploy applications ---
info "Waiting for ArgoCD root application to sync..."

# Give the controller a moment to create the application object and its status
sleep 5

# Wait for root application to be synced first
max_attempts=20
attempt=0
while [ $attempt -lt $max_attempts ]; do
    set +e
    app_exists=$(kubectl get application root-prod -n argocd >/dev/null 2>&1; echo $?)
    if [ "$app_exists" -eq 0 ]; then
        app_status=$(kubectl get application root-prod -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
        health_status=$(kubectl get application root-prod -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
        
        app_status=${app_status:-"Waiting"}
        health_status=${health_status:-"Waiting"}

        info "Root application sync status: $app_status, health: $health_status"
        
        if [ "$app_status" = "Synced" ]; then
            set -e
            info "Root application is synced! Child applications are now being created."
            break
        fi
    else
        info "Root application not found yet"
    fi
    
    info "Waiting for root application to sync... (attempt $((attempt+1))/$max_attempts)"
    sleep 10
    ((attempt++))
    set -e
done

if [ $attempt -eq $max_attempts ]; then
    error "Root application failed to sync. Aborting."
fi

info "Waiting for wave 0 applications to be healthy..."
# Wait for critical wave 0 applications to be healthy before proceeding
wave0_apps=("prod-namespace" "prod-cloudnative-pg-crds")
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    set +e
    all_healthy=true
    for app in "${wave0_apps[@]}"; do
        app_exists=$(kubectl get application "$app" -n argocd >/dev/null 2>&1; echo $?)
        if [ "$app_exists" -eq 0 ]; then
            app_status=$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
            health_status=$(kubectl get application "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
            
            app_status=${app_status:-"Unknown"}
            health_status=${health_status:-"Unknown"}
            
            info "Application $app: sync=$app_status, health=$health_status"
            
            if [ "$app_status" != "Synced" ] || [ "$health_status" != "Healthy" ]; then
                all_healthy=false
            fi
        else
            info "Application $app not found yet"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        set -e
        info "All wave 0 applications are healthy!"
        break
    fi
    
    info "Waiting for wave 0 applications to be healthy... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
    set -e
done

if [ $attempt -eq $max_attempts ]; then
    info "Warning: Not all wave 0 applications are healthy. Proceeding anyway..."
fi

info "Waiting for spezistudyplatform namespace to be created..."
# Wait for namespace to exist with retry logic
max_attempts=20
attempt=0
while [ $attempt -lt $max_attempts ]; do
    set +e
    namespace_exists=$(kubectl get namespace spezistudyplatform >/dev/null 2>&1; echo $?)
    set -e
    
    if [ "$namespace_exists" -eq 0 ]; then
        info "Namespace spezistudyplatform found!"
        break
    fi
    
    info "Waiting for namespace to be created... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
    error "spezistudyplatform namespace not found after waiting. Check ArgoCD sync status."
fi

info "Auth application will be synced by ArgoCD automatically."
info "Proceeding with Keycloak setup without waiting for auth application health."

info "Waiting for Keycloak to be ready..."
# Wait for Keycloak statefulset and pod to be ready
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    set +e
    statefulset_exists=$(kubectl get statefulset keycloak -n spezistudyplatform >/dev/null 2>&1; echo $?)
    if [ "$statefulset_exists" -eq 0 ]; then
        # Check if pod is ready
        pod_ready=$(kubectl get pod keycloak-0 -n spezistudyplatform -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$pod_ready" = "True" ]; then
            set -e
            info "Keycloak is ready!"
            break
        else
            info "Keycloak pod exists but not ready yet..."
        fi
    else
        info "Waiting for Keycloak statefulset to be created..."
    fi
    
    info "Waiting for Keycloak to be ready... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
    set -e
done

if [ $attempt -eq $max_attempts ]; then
    error "Keycloak not ready after waiting. Check ArgoCD sync status."
fi

# --- 8. Create GCP Service Account Secret for External Secrets ---
info "Creating GCP service account secret for External Secrets..."

# Create external-secrets-system namespace if it doesn't exist
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

# Create GCP service account secret for external-secrets operator
kubectl create secret generic gcp-sa-key --from-file=secret-access-credentials="$CREDENTIALS_FILE" -n external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

info "GCP service account secret created for External Secrets."

# --- 9. Bootstrap Keycloak for Production ---
info "Bootstrapping Keycloak realm and OAuth2 proxy configuration for production..."

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
    error "Keycloak is not ready after waiting."
fi

# Run Tofu bootstrap for production
cd "$SCRIPT_DIR/tofu/keycloak-bootstrap/tf"
TERRAFORM_CMD="tofu"
if ! command -v tofu &> /dev/null; then
    TERRAFORM_CMD="terraform"
fi

info "Running Keycloak bootstrap with $TERRAFORM_CMD for production..."
$TERRAFORM_CMD init
$TERRAFORM_CMD apply \
    -var="keycloak_url=http://localhost:8081/auth" \
    -var="keycloak_password=admin123!" \
    -var="frontend_url=https://$PRODUCTION_DOMAIN" \
    -var="gcp_project_id=$GCP_PROJECT_ID" \
    -auto-approve

info "Keycloak bootstrap completed successfully!"

# Store ArgoCD client secret in GCP Secret Manager
info "Storing ArgoCD client secret in GCP Secret Manager..."
ARGOCD_CLIENT_SECRET=$($TERRAFORM_CMD output -raw argocd_client_secret)
echo "$ARGOCD_CLIENT_SECRET" | gcloud secrets create keycloak-argocd-client --data-file=- --project="$GCP_PROJECT_ID" || \
    echo "$ARGOCD_CLIENT_SECRET" | gcloud secrets versions add keycloak-argocd-client --data-file=- --project="$GCP_PROJECT_ID"
info "ArgoCD client secret stored in GCP Secret Manager."

# Get Google OAuth client ID for display (created automatically by Terraform)
info "Google OAuth client will be created automatically by Terraform..."
GOOGLE_CLIENT_ID=$($TERRAFORM_CMD output -raw google_oauth_client_id 2>/dev/null || echo "will-be-created-by-terraform")
info "Google OAuth credentials are automatically stored in GCP Secret Manager."

cd "$SCRIPT_DIR"

# --- 9. Final setup message ---
info "Production setup complete!"
info "ArgoCD is now configured to manage the production environment."
info "Applications will be deployed in waves. Monitor progress in the ArgoCD UI."
info ""
info "=== Access Information ==="
info "Production URL: https://$PRODUCTION_DOMAIN"
info "Static IP configured: $STATIC_IP"
info ""
info "=== Google SSO Information ==="
info "Google SSO has been configured in Keycloak!"
info "Users can now sign in with their Google accounts at: https://$PRODUCTION_DOMAIN/auth"
info "Google OAuth Client ID: $GOOGLE_CLIENT_ID"
info "OAuth credentials have been stored in GCP Secret Manager"
info ""
info "To access the ArgoCD UI:"
echo "ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo ""
info "To port-forward the ArgoCD UI, run:"
info "kubectl port-forward svc/argocd-server -n argocd 8080:443"
info ""
info "Monitor application status with:"
info "kubectl get applications -n argocd"