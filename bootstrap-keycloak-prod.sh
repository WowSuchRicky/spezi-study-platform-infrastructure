#!/bin/bash
set -e

# --- Configuration ---
PRODUCTION_DOMAIN="platform.spezi.stanford.edu"

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
    -auto-approve

info "Keycloak bootstrap completed successfully!"

cd "$SCRIPT_DIR"

info "Keycloak realm 'spezistudyplatform' has been created and configured."
info "OAuth2 proxy should now be able to connect to Keycloak successfully."
info "You can now restart the oauth2-proxy pods to pick up the new realm configuration:"
info "kubectl rollout restart deployment oauth2-proxy -n spezistudyplatform"