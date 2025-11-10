#!/bin/bash
set -e

# --- Configuration ---
PRODUCTION_DOMAIN="platform.spezi.stanford.edu"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-spezistudyplatform-dev}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-spezistudyplatform-tf-state-prod}"
TF_STATE_PREFIX="${TF_STATE_PREFIX:-terraform/state/keycloak-bootstrap}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-}"
KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-}"

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

# --- Bootstrap Keycloak for Production ---
info "Bootstrapping Keycloak realm and OAuth2 proxy configuration for production..."

# Check if Keycloak is running
if ! kubectl get pod keycloak-0 -n spezistudyplatform >/dev/null 2>&1; then
    error "Keycloak pod not found. Make sure the production environment is deployed first."
fi

# Port forward to access Keycloak
info "Setting up port forward to Keycloak..."
kubectl port-forward -n spezistudyplatform svc/keycloak 8081:80 &
PORT_FORWARD_PID=$!
info "Port forward PID: $PORT_FORWARD_PID"
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

# Fetch admin password from existing Kubernetes secret when not provided
if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
    KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak -n spezistudyplatform -o jsonpath="{.data['admin-password']}" 2>/dev/null | base64 --decode | tr -d '\n')
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        error "Unable to retrieve Keycloak admin password from secret. Set KEYCLOAK_ADMIN_PASSWORD env var or ensure the secret exists."
    fi
fi

if [ -z "$KEYCLOAK_ADMIN_USERNAME" ]; then
    KEYCLOAK_ADMIN_USERNAME=$(kubectl get secret keycloak -n spezistudyplatform -o jsonpath="{.data['admin-username']}" 2>/dev/null | base64 --decode | tr -d '\n')
    if [ -z "$KEYCLOAK_ADMIN_USERNAME" ]; then
        KEYCLOAK_ADMIN_USERNAME="user"
    fi
fi

info "Using Keycloak admin username from secret: $KEYCLOAK_ADMIN_USERNAME"

# Validate admin credentials before running Terraform to surface helpful errors
token_response_file=$(mktemp)
token_status=$(curl -s -w '%{http_code}' -o "$token_response_file" \
  -X POST "http://localhost:8081/auth/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=admin-cli" \
  --data-urlencode "username=$KEYCLOAK_ADMIN_USERNAME" \
  --data-urlencode "password=$KEYCLOAK_ADMIN_PASSWORD" \
  --data-urlencode "grant_type=password")

if [ "$token_status" != "200" ]; then
    error "Failed to authenticate to Keycloak (HTTP $token_status). Response: $(cat "$token_response_file")"
fi

rm -f "$token_response_file"

# Optionally clear remote and local Terraform state for Keycloak bootstrap
if [ "${RESET_KEYCLOAK_STATE:-0}" = "1" ]; then
    info "RESET_KEYCLOAK_STATE=1, removing existing Terraform state before reinitialising."
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
# Export sensitive vars before running Terraform so both init and apply can use them
export TF_VAR_keycloak_password="$KEYCLOAK_ADMIN_PASSWORD"
export TF_VAR_keycloak_username="$KEYCLOAK_ADMIN_USERNAME"
export TF_VAR_keycloak_client_id="admin-cli"
export TF_VAR_create_test_users="false"
$TERRAFORM_CMD init \
    -migrate-state \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="prefix=${TF_STATE_PREFIX}"

# Attempt to import existing Keycloak resources to avoid API conflicts when state was reset
if ! $TERRAFORM_CMD state list 2>/dev/null | grep -q 'keycloak_realm.realm'; then
    info "Importing existing Keycloak configuration into Terraform state..."
    declare -a IMPORT_RESOURCES=(
      "keycloak_realm.realm=spezistudyplatform"
      "keycloak_openid_client.oauth2_proxy_client=spezistudyplatform/oauth2-proxy"
      "keycloak_openid_client.argocd_client=spezistudyplatform/argocd"
      "keycloak_role.authorized_users=spezistudyplatform/spezistudyplatform-authorized-users"
      "keycloak_role.argocd_admins=spezistudyplatform/ArgoCDAdmins"
      "keycloak_oidc_identity_provider.google=spezistudyplatform/google"
      "keycloak_openid_client_scope.groups_scope=spezistudyplatform/groups"
      "keycloak_openid_client_optional_scopes.oauth2_proxy_groups_scope=spezistudyplatform/oauth2-proxy/groups"
      "keycloak_openid_client_optional_scopes.argocd_groups_scope=spezistudyplatform/argocd/groups"
      "keycloak_custom_identity_provider_mapper.google_email_mapper=spezistudyplatform/google/email-mapper"
      "keycloak_custom_identity_provider_mapper.google_first_name_mapper=spezistudyplatform/google/first-name-mapper"
      "keycloak_custom_identity_provider_mapper.google_last_name_mapper=spezistudyplatform/google/last-name-mapper"
      "keycloak_custom_identity_provider_mapper.google_username_mapper=spezistudyplatform/google/username-mapper"
      "keycloak_custom_identity_provider_mapper.google_email_verified_mapper=spezistudyplatform/google/email-verified-mapper"
    )

    for mapping in "${IMPORT_RESOURCES[@]}"; do
      resource="${mapping%%=*}"
      identifier="${mapping#*=}"
      if $TERRAFORM_CMD state list 2>/dev/null | grep -q "$resource"; then
        continue
      fi
      info "Importing $resource"
      if ! $TERRAFORM_CMD import "$resource" "$identifier" >/dev/null 2>&1; then
        info "  Skipped importing $resource (resource not found or already managed)"
      fi
    done
fi

$TERRAFORM_CMD apply \
    -var="keycloak_url=http://localhost:8081/auth" \
    -var="frontend_url=https://$PRODUCTION_DOMAIN" \
    -var="gcp_project_id=${GCP_PROJECT_ID}" \
    -var="enable_google_sso=true" \
    -auto-approve

rm -f "$BACKEND_FILE"

unset TF_VAR_keycloak_password TF_VAR_keycloak_username TF_VAR_keycloak_client_id TF_VAR_create_test_users

info "Keycloak bootstrap completed successfully!"

cd "$SCRIPT_DIR"

info "Keycloak realm 'spezistudyplatform' has been created and configured."
info "OAuth2 proxy should now be able to connect to Keycloak successfully."
info "You can now restart the oauth2-proxy pods to pick up the new realm configuration:"
info "kubectl rollout restart deployment oauth2-proxy -n spezistudyplatform"
