#!/bin/bash
set -e

# --- Configuration ---
# TODO: eventually get this from a more centralized config location or from GKE directly
GKE_CLUSTER_NAME="spezistudyplatform-dev-gke"
GCP_PROJECT_ID="spezistudyplatform-dev"
GCP_ZONE="us-west1-c"
PRODUCTION_DOMAIN="platform.spezi.stanford.edu"
STATIC_IP="34.168.138.135"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-spezistudyplatform-tf-state-prod}"
TF_STATE_PREFIX="${TF_STATE_PREFIX:-terraform/state/keycloak-bootstrap}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_EMAIL:-spezistudyplatform-dev-svc@${GCP_PROJECT_ID}.iam.gserviceaccount.com}"
KEYCLOAK_REALM="spezistudyplatform"
KEYCLOAK_BASE_URL="http://localhost:8081/auth"
KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-}"
SPEZI_SERVICE_NAME="${SPEZI_SERVICE_NAME:-spezistudyplatform}"
GKE_TF_STATE_PREFIX="${GKE_TF_STATE_PREFIX:-gke/${SPEZI_SERVICE_NAME}}"
ACTION="setup"
AUTO_APPROVED=0

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$SCRIPT_DIR/gcp-service-account-key.json}"

# --- Helper Functions ---
info() {
    echo "INFO: $1"
}

error() {
    echo "ERROR: $1"
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./setup-prod.sh [options]

Options:
  --teardown, --destroy   Destroy production infrastructure instead of provisioning it.
  --yes, -y               Auto-approve prompts for destructive actions.
  -h, --help              Show this help message.

Environment variables such as TF_STATE_BUCKET, TF_STATE_PREFIX, and
SPEZI_SERVICE_NAME may be used to override defaults.
EOF
}

trap 'cleanup' EXIT

BACKEND_FILE=""

cleanup() {
    info "Cleaning up..."
    if [ -n "$PORT_FORWARD_PID" ] && ps -p $PORT_FORWARD_PID > /dev/null; then
        kill $PORT_FORWARD_PID
    fi
    if [ -n "$BACKEND_FILE" ] && [ -f "$BACKEND_FILE" ]; then
        rm -f "$BACKEND_FILE"
    fi
}

fetch_keycloak_client_secret() {
    local base_url="$1"
    local realm="$2"
    local admin_user="$3"
    local admin_password="$4"
    local client_id="$5"

    local token
    token=$(curl -s -X POST "${base_url%/}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=admin-cli" \
        -d "username=$admin_user" \
        -d "password=$admin_password" \
        -d "grant_type=password" | python3 -c 'import json, sys; data=json.load(sys.stdin); print(data.get("access_token", ""))')

    if [ -z "$token" ]; then
        error "Failed to authenticate with Keycloak admin API to retrieve client secret."
    fi

    local client_uuid
    client_uuid=$(curl -s -H "Authorization: Bearer $token" \
        "${base_url%/}/admin/realms/$realm/clients?clientId=$client_id" | \
        python3 -c 'import json, sys; data=json.load(sys.stdin); print(data[0]["id"] if data else "")')

    if [ -z "$client_uuid" ]; then
        error "Unable to locate client '$client_id' in realm '$realm'."
    fi

    local secret
    secret=$(curl -s -H "Authorization: Bearer $token" \
        "${base_url%/}/admin/realms/$realm/clients/$client_uuid/client-secret" | \
        python3 -c 'import json, sys; data=json.load(sys.stdin); print(data.get("value", ""))')

    if [ -z "$secret" ]; then
        info "Keycloak client '$client_id' did not return a secret; continuing without storing it."
        echo ""
        return 0
    fi

    echo "$secret"
}

get_keycloak_admin_token() {
    local response
    response=$(curl -s -w '\n%{http_code}' -X POST "${KEYCLOAK_BASE_URL%/}/realms/master/protocol/openid-connect/token" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "client_id=admin-cli" \
        --data-urlencode "username=$KEYCLOAK_ADMIN_USERNAME" \
        --data-urlencode "password=$KEYCLOAK_ADMIN_PASSWORD" \
        --data-urlencode 'grant_type=password')

    local status token_json
    status=$(echo "$response" | tail -n1)
    token_json=$(echo "$response" | head -n-1)

    if [ "$status" != "200" ] || [ -z "$token_json" ]; then
        echo ""
        return 1
    fi

    python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("access_token", ""))' <<< "$token_json"
}

get_keycloak_client_uuid() {
    local client_id="$1"
    local token="$2"
    if [ -z "$token" ]; then
        echo ""
        return 0
    fi
    local response status body
    response=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $token" \
        "${KEYCLOAK_BASE_URL%/}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${client_id}") || return 0
    status=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    if [ "$status" != "200" ] || [ -z "$body" ]; then
        info "  Failed to fetch client '$client_id' (status: $status)"
        echo ""
        return 0
    fi
    printf '%s' "$body" | python3 - <<'PY'
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)
if isinstance(data, list) and data:
    print(data[0].get("id", ""))
else:
    print("")
PY
}

get_keycloak_client_scope_id() {
    local scope_name="$1"
    local token="$2"
    if [ -z "$token" ]; then
        echo ""
        return 0
    fi
    local response status body
    response=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $token" \
        "${KEYCLOAK_BASE_URL%/}/admin/realms/${KEYCLOAK_REALM}/client-scopes") || return 0
    status=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    if [ "$status" != "200" ] || [ -z "$body" ]; then
        info "  Failed to fetch client scopes (status: $status)"
        echo ""
        return 0
    fi
    printf '%s' "$body" | python3 - "$scope_name" <<'PY'
import json, sys
scope_name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)
for scope in data:
    if scope.get("name") == scope_name:
        print(scope.get("id", ""))
        break
else:
    print("")
PY
}

keycloak_identity_provider_exists() {
    local alias="$1"
    local token="$2"
    if [ -z "$token" ]; then
        return 1
    fi
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" \
        "${KEYCLOAK_BASE_URL%/}/admin/realms/${KEYCLOAK_REALM}/identity-provider/instances/${alias}")
    [ "$status" = "200" ]
}

get_keycloak_role_id() {
    local role_name="$1"
    local token="$2"
    if [ -z "$token" ]; then
        echo ""
        return 0
    fi
    local response status body
    response=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $token" \
        "${KEYCLOAK_BASE_URL%/}/admin/realms/${KEYCLOAK_REALM}/roles/${role_name}") || return 0
    status=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    if [ "$status" != "200" ] || [ -z "$body" ]; then
        info "  Failed to fetch role '$role_name' (status: $status)"
        echo ""
        return 0
    fi
    printf '%s' "$body" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print("")
    raise SystemExit(0)
print(data.get("id", ""))
PY
}

check_prereqs() {
    info "Checking prerequisites..."

    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi

    if ! command -v kubectl &> /dev/null; then
        if [ "$ACTION" = "setup" ]; then
            error "kubectl is not installed. Please install it first."
        else
            info "kubectl is not installed. Continuing teardown without it."
        fi
    fi

    if ! command -v ansible-playbook &> /dev/null; then
        if [ "$ACTION" = "setup" ]; then
            error "ansible is not installed. Please install it first."
        else
            info "ansible-playbook is not installed. Skipping (not required for teardown)."
        fi
    fi

    if ! command -v tofu &> /dev/null && ! command -v terraform &> /dev/null; then
        error "tofu or terraform is not installed. Please install one of them first."
    fi

    if [ "$ACTION" = "setup" ] && ! command -v python3 &> /dev/null; then
        error "python3 is required for parsing Keycloak API responses."
    fi
}

destroy_gke_infrastructure() {
    info "Destroying GKE infrastructure with Terraform..."

    local terraform_dir="$SCRIPT_DIR/tofu/gke"
    if [ ! -d "$terraform_dir" ]; then
        error "Terraform directory for GKE not found at $terraform_dir"
    fi

    local terraform_cmd="tofu"
    if ! command -v tofu &> /dev/null; then
        terraform_cmd="terraform"
    fi

    pushd "$terraform_dir" >/dev/null

    local backend_file="$PWD/backend-prod.tf"
    cat > "$backend_file" <<'EOF'
terraform {
  backend "gcs" {}
}
EOF
    BACKEND_FILE="$backend_file"

    info "Initializing Terraform backend for GKE teardown..."
    $terraform_cmd init \
        -migrate-state \
        -backend-config="bucket=$TF_STATE_BUCKET" \
        -backend-config="prefix=$GKE_TF_STATE_PREFIX"

    if command -v gsutil >/dev/null 2>&1; then
        local lock_object="gs://${TF_STATE_BUCKET}/${GKE_TF_STATE_PREFIX}/default.tflock"
        if gsutil ls "$lock_object" >/dev/null 2>&1; then
            info "Clearing remote state lock at $lock_object..."
            gsutil rm "$lock_object" >/dev/null 2>&1 || true
        fi
    fi

    if [ "$AUTO_APPROVED" -ne 1 ]; then
        local response
        read -r -p "This will destroy the production GKE cluster and associated resources. Proceed? [y/N] " response || response=""
        case "$response" in
            [yY][eE][sS]|[yY])
                info "Proceeding with Terraform destroy..."
                ;;
            *)
                info "Teardown cancelled by user; leaving resources intact."
                rm -f "$backend_file"
                BACKEND_FILE=""
                popd >/dev/null
                return 1
                ;;
        esac
    else
        info "Auto-approve enabled; skipping confirmation prompt."
    fi

    local destroy_targets=()
    local has_targets=0
    local state_resources
    if state_resources=$($terraform_cmd state list 2>/dev/null); then
        while IFS= read -r resource; do
            [ -z "$resource" ] && continue
            if [ "$resource" = "google_compute_address.ip_address" ]; then
                info "Preserving static IP resource ($resource); it will remain allocated."
                continue
            fi
            destroy_targets+=("-target=$resource")
            has_targets=1
        done <<< "$state_resources"
    else
        rm -f "$backend_file"
        BACKEND_FILE=""
        popd >/dev/null
        error "Unable to read Terraform state; aborting teardown to avoid deleting the static IP."
    fi

    if [ "$has_targets" -eq 0 ]; then
        info "No Terraform-managed resources require teardown (static IP retained)."
    else
        if ! $terraform_cmd destroy -auto-approve "${destroy_targets[@]}"; then
            rm -f "$backend_file"
            BACKEND_FILE=""
            popd >/dev/null
            error "Terraform destroy failed for GKE."
        fi
    fi

    rm -f "$backend_file"
    BACKEND_FILE=""
    popd >/dev/null

    info "GKE infrastructure destroyed successfully."
    return 0
}

teardown_prod() {
    check_prereqs

    info "Preparing to tear down production infrastructure..."

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        info "No active gcloud authentication found. Please authenticate:"
        gcloud auth login
    fi

    info "Setting GCP project to $GCP_PROJECT_ID"
    gcloud config set project "$GCP_PROJECT_ID"

    if [ ! -f "$CREDENTIALS_FILE" ]; then
        error "Service account key not found at $CREDENTIALS_FILE. Run setup-prod.sh first or set CREDENTIALS_FILE."
    fi

    info "Activating service account for infrastructure operations..."
    gcloud auth activate-service-account --key-file="$CREDENTIALS_FILE"

    export GOOGLE_APPLICATION_CREDENTIALS="$CREDENTIALS_FILE"

    if destroy_gke_infrastructure; then
        info "Production teardown complete. GKE resources have been destroyed."
    else
        info "Teardown cancelled. Infrastructure remains in place."
    fi
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --teardown|--destroy|teardown|destroy)
            ACTION="teardown"
            shift
            ;;
        --yes|-y|--auto-approve)
            AUTO_APPROVED=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unrecognized option '$1'"
            ;;
    esac
done

if [ "$ACTION" = "teardown" ]; then
    teardown_prod
    exit 0
fi

# --- Prerequisites Check ---
check_prereqs

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
    set -e
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
    if curl --output /dev/null --silent --head --fail "$KEYCLOAK_BASE_URL/"; then
        info "Keycloak is ready!"
        break
    fi
    info "Waiting for Keycloak to be ready... (attempt $((attempt+1))/$max_attempts)"
    sleep 10
    ((attempt++))
    set -e
done

if [ $attempt -eq $max_attempts ]; then
    error "Keycloak is not ready after waiting."
fi

# Fetch admin password from Kubernetes secret when not provided
if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
    KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak -n spezistudyplatform -o jsonpath="{.data['admin-password']}" 2>/dev/null | base64 --decode | tr -d '\n')
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        error "Unable to retrieve Keycloak admin password from secret. Set KEYCLOAK_ADMIN_PASSWORD env var or ensure the secret exists."
    fi
fi

if [ -z "$KEYCLOAK_ADMIN_USERNAME" ]; then
    KEYCLOAK_ADMIN_USERNAME=$(kubectl get secret keycloak -n spezistudyplatform -o jsonpath="{.data['admin-username']}" 2>/dev/null | base64 --decode | tr -d '\n' || true)
fi

# Ensure we always have a usable admin username (Bitnami chart defaults to "user")
KEYCLOAK_ADMIN_USERNAME=${KEYCLOAK_ADMIN_USERNAME:-user}

info "Using Keycloak admin username from secret: $KEYCLOAK_ADMIN_USERNAME"

KEYCLOAK_ADMIN_TOKEN=$(get_keycloak_admin_token)
if [ -z "$KEYCLOAK_ADMIN_TOKEN" ]; then
    error "Failed to authenticate to Keycloak using provided admin credentials."
fi

if [ "${RESET_KEYCLOAK_STATE:-0}" = "1" ]; then
    info "RESET_KEYCLOAK_STATE=1, removing existing Terraform state before Keycloak bootstrap."
    gsutil rm -f "gs://${TF_STATE_BUCKET}/${TF_STATE_PREFIX}/default.tfstate" >/dev/null 2>&1 || true
    gsutil rm -f "gs://${TF_STATE_BUCKET}/${TF_STATE_PREFIX}/default.tfstate.backup" >/dev/null 2>&1 || true
    rm -rf "$SCRIPT_DIR/tofu/keycloak-bootstrap/tf/.terraform" "$SCRIPT_DIR/tofu/keycloak-bootstrap/tf/terraform.tfstate"* >/dev/null 2>&1 || true
fi

# Run Tofu bootstrap for production
cd "$SCRIPT_DIR/tofu/keycloak-bootstrap/tf"
TERRAFORM_CMD="tofu"
if ! command -v tofu &> /dev/null; then
    TERRAFORM_CMD="terraform"
fi

BACKEND_FILE="$PWD/backend-prod.tf"
cat > "$BACKEND_FILE" <<'EOF'
terraform {
  backend "gcs" {}
}
EOF

info "Running Keycloak bootstrap with $TERRAFORM_CMD for production..."
export TF_VAR_keycloak_password="$KEYCLOAK_ADMIN_PASSWORD"
export TF_VAR_keycloak_username="$KEYCLOAK_ADMIN_USERNAME"
export TF_VAR_keycloak_client_id="admin-cli"
export TF_VAR_keycloak_url="$KEYCLOAK_BASE_URL"
export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
export TF_VAR_enable_google_sso="true"
export TF_VAR_create_test_users="false"

$TERRAFORM_CMD init \
    -migrate-state \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="prefix=$TF_STATE_PREFIX"

if command -v gsutil >/dev/null 2>&1; then
    LOCK_OBJECT="gs://${TF_STATE_BUCKET}/${TF_STATE_PREFIX}/default.tflock"
    if gsutil ls "$LOCK_OBJECT" >/dev/null 2>&1; then
        info "Found existing remote state lock at $LOCK_OBJECT; attempting to remove it before import"
        gsutil rm "$LOCK_OBJECT" >/dev/null 2>&1 || true
    else
        info "No existing remote state lock found at $LOCK_OBJECT before import"
    fi
fi

# Manual imports for existing Keycloak configuration
# (A temporary workaround while cleaning up state)
info "Skipping automatic import (temporary)"

if command -v gsutil >/dev/null 2>&1; then
    LOCK_OBJECT="gs://${TF_STATE_BUCKET}/${TF_STATE_PREFIX}/default.tflock"
    if gsutil ls "$LOCK_OBJECT" >/dev/null 2>&1; then
        info "Ensuring remote state lock is cleared before apply ($LOCK_OBJECT)"
        gsutil rm "$LOCK_OBJECT" >/dev/null 2>&1 || true
    fi
fi

$TERRAFORM_CMD apply \
    -var="keycloak_url=$KEYCLOAK_BASE_URL" \
    -var="frontend_url=https://$PRODUCTION_DOMAIN" \
    -var="gcp_project_id=$GCP_PROJECT_ID" \
    -var="enable_google_sso=true" \
    -auto-approve

rm -f "$BACKEND_FILE"
BACKEND_FILE=""

unset TF_VAR_keycloak_password TF_VAR_keycloak_username TF_VAR_keycloak_client_id TF_VAR_keycloak_url TF_VAR_gcp_project_id TF_VAR_enable_google_sso TF_VAR_create_test_users

info "Keycloak bootstrap completed successfully!"

# Store ArgoCD client secret in GCP Secret Manager
info "Storing ArgoCD client secret in GCP Secret Manager..."
ARGOCD_CLIENT_SECRET=$(fetch_keycloak_client_secret "$KEYCLOAK_BASE_URL" "$KEYCLOAK_REALM" "$KEYCLOAK_ADMIN_USERNAME" "$KEYCLOAK_ADMIN_PASSWORD" "argocd")

if [ -n "$ARGOCD_CLIENT_SECRET" ]; then
    echo "$ARGOCD_CLIENT_SECRET" | gcloud secrets create keycloak-argocd-client --data-file=- --project="$GCP_PROJECT_ID" || \
        echo "$ARGOCD_CLIENT_SECRET" | gcloud secrets versions add keycloak-argocd-client --data-file=- --project="$GCP_PROJECT_ID"
    info "ArgoCD client secret stored in GCP Secret Manager."
else
    info "Keycloak client 'argocd' does not expose a secret; skipping GCP Secret Manager sync."
fi

# Get Google OAuth client ID for display (created automatically by Terraform)
info "Google OAuth client will be created automatically by Terraform..."
GOOGLE_CLIENT_ID=$(gcloud secrets versions access latest --secret=keycloak-google-sso-client-id --project="$GCP_PROJECT_ID" 2>/dev/null || echo "stored-in-secret-manager")
info "Google OAuth credentials are automatically stored in GCP Secret Manager."

info "Ensuring Argo CD application is healthy before finalizing..."
wave3_apps=("prod-argocd")
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    set +e
    all_healthy=true
    for app in "${wave3_apps[@]}"; do
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
        info "Argo CD application is healthy!"
        break
    fi

    info "Waiting for Argo CD application to be healthy... (attempt $((attempt+1))/$max_attempts)"
    sleep 15
    ((attempt++))
    set -e  # Re-enable exit on error at the very end of loop iteration

done

if [ $attempt -eq $max_attempts ]; then
    info "Warning: Argo CD application is not healthy. Proceeding anyway..."
fi

if kubectl -n argocd get deployment argocd-server >/dev/null 2>&1; then
    info "Restarting Argo CD server to pick up configuration updates..."
    kubectl -n argocd rollout restart deployment argocd-server >/dev/null
    kubectl -n argocd rollout status deployment argocd-server --timeout=180s >/dev/null || true
else
    info "Argo CD server deployment not available yet; skipping restart."
fi

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
