#!/bin/bash

set -e

# --- Configuration ---
LOCAL_DEV_DIR="./local-dev"
KUBE_SRC_DIR="./kube"
KUBE_DEST_DIR="$LOCAL_DEV_DIR/kube"
KIND_CLUSTER_NAME="spezi-study-platform"
# Get the local IP address dynamically
LOCAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
LOCAL_DOMAIN="${LOCAL_IP}.nip.io"
PROD_DOMAIN1="platform.spezi.stanford.edu"
PROD_DOMAIN2="study.muci.sh"

# --- Helper Functions ---
info() {
    echo "INFO: $1"
}

# --- Main Logic ---

helm repo add traefik https://traefik.github.io/charts
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests


# 1. Prepare manifests for local deployment
info "Preparing Kubernetes manifests for local deployment..."
if [ -d "$KUBE_DEST_DIR" ]; then
  rm -rf "$KUBE_DEST_DIR"
fi
cp -r "$KUBE_SRC_DIR" "$KUBE_DEST_DIR"

info "Replacing production domains with local domain ($LOCAL_DOMAIN)..."
find "$KUBE_DEST_DIR" -type f -name "*.yaml" -exec sed -i.bak "s/$PROD_DOMAIN1/$LOCAL_DOMAIN/g" {} +
find "$KUBE_DEST_DIR" -type f -name "*.yaml" -exec sed -i.bak "s/$PROD_DOMAIN2/$LOCAL_DOMAIN/g" {} +
find "$KUBE_DEST_DIR" -type f -name "*.tf" -exec sed -i.bak "s/$PROD_DOMAIN1/$LOCAL_DOMAIN/g" {} +
find "$KUBE_DEST_DIR" -type f -name "*.tf" -exec sed -i.bak "s/$PROD_DOMAIN2/$LOCAL_DOMAIN/g" {} +

info "Configuring cert-manager for local development..."
# Use Let's Encrypt staging server to avoid rate limits
sed -i.bak "s|server: https://acme-v02.api.letsencrypt.org/directory|server: https://acme-staging-v02.api.letsencrypt.org/directory|g" "$KUBE_DEST_DIR/cert-manager/certissuer.yaml"
sed -i.bak "s|letsencrypt-prod|letsencrypt-staging|g" "$KUBE_DEST_DIR/cert-manager/certissuer.yaml"
# Update ingress annotations to use the staging issuer
find "$KUBE_DEST_DIR" -type f -name "*.yaml" -exec sed -i.bak "s|letsencrypt-prod|letsencrypt-staging|g" {} +
rm -rf "$KUBE_DEST_DIR/argocd"

info "Adjusting oauth2-proxy for local development..."
sed -i.bak 's/--code-challenge-method=S256/--code-challenge-method=S256\n  - --insecure-oidc-skip-issuer-verification=true/' "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-values.yaml"
sed -i.bak "s/--whitelist-domain=\*\.spezi\.stanford\.edu/--whitelist-domain=*.$LOCAL_IP.nip.io/" "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-values.yaml"
sed -i.bak 's/--insecure-oidc-skip-issuer-verification=true/--insecure-oidc-skip-issuer-verification=true\n  - --ssl-insecure-skip-verify=true\n  - --cookie-secure=false/' "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-values.yaml"

# OAuth2-proxy uses external domain (same as production) - domain replacement handles this automatically

# Keycloak uses minimal config (same as production) - no hostname overrides needed

info "Enabling oauth2-proxy middleware..."
sed -i.bak 's/# middlewares:/middlewares:/g' "$KUBE_DEST_DIR/traefik/main-service-ingress.yaml"
sed -i.bak 's/# - name: oauth2-proxy/- name: oauth2-proxy/g' "$KUBE_DEST_DIR/traefik/main-service-ingress.yaml"
sed -i.bak 's/# - name: oauth2-errors/- name: oauth2-errors/g' "$KUBE_DEST_DIR/traefik/main-service-ingress.yaml"

info "Keeping Postgres Operator configuration..."
# The local setup will now use the CloudNativePG operator, same as production.
info "Disabling PodMonitor for local development..."
sed -i.bak 's/enablePodMonitor: true/enablePodMonitor: false/g' "$KUBE_DEST_DIR/db/postgres-with-operator.yaml"

info "Replacing sealed secrets with development secrets..."
find "$KUBE_DEST_DIR" -type f -name "*.sealed.yaml" -delete

# oauth2-proxy secret
info "Generating random secret for oauth2-proxy..."
OAUTH2_PROXY_CLIENT_SECRET=$(openssl rand -hex 32)
cp "$KUBE_SRC_DIR/auth/oauth2-proxy/oauth2proxy-secret.yaml.example" "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-secret.yaml"
COOKIE_SECRET=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d -- '\n' | tr -- '+/' '-_')
sed -i.bak "s/generate_with_above_command/$COOKIE_SECRET/" "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-secret.yaml"
sed -i.bak "s/retrieve_from_kc/$OAUTH2_PROXY_CLIENT_SECRET/" "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-secret.yaml"

# DB password secret
info "Generating random password for the database..."
DB_PASSWORD=$(openssl rand -hex 32)
DB_USER="spezistudyplatform"
DB_USER_B64=$(echo -n "$DB_USER" | base64)
DB_PASSWORD_B64=$(echo -n "$DB_PASSWORD" | base64)
cp "$KUBE_SRC_DIR/db/db-pw-secret.yaml.example" "$KUBE_DEST_DIR/db/db-pw-secret.yaml"
sed -i.bak "s|username: YWJjCg==|username: $DB_USER_B64|" "$KUBE_DEST_DIR/db/db-pw-secret.yaml"
sed -i.bak "s|password: YWJjCg==|password: $DB_PASSWORD_B64|" "$KUBE_DEST_DIR/db/db-pw-secret.yaml"

# Backend secret
info "Generating random OAUTH_CLIENT_SECRET for the backend..."
BACKEND_OAUTH_CLIENT_SECRET_B64=$(openssl rand -base64 32 | tr -d '\n')
cp "$KUBE_SRC_DIR/backend/secret.yaml.example" "$KUBE_DEST_DIR/backend/secret.yaml"
sed -i.bak "s|OAUTH_CLIENT_SECRET: \"\"|OAUTH_CLIENT_SECRET: $BACKEND_OAUTH_CLIENT_SECRET_B64|" "$KUBE_DEST_DIR/backend/secret.yaml"

# Frontend secret
cp "$KUBE_SRC_DIR/frontend/secret.yaml.example" "$KUBE_DEST_DIR/frontend/secret.yaml"

info "Adjusting imagePullPolicy for local development..."
find "$KUBE_DEST_DIR" -type f -name "deployment.yaml" -exec sed -i.bak 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' {} +

find "$KUBE_DEST_DIR" -type f -name "*.bak" -delete

info "Adjusting Traefik values for local deployment..."
sed -i.bak 's/loadBalancerIP: "34.168.131.83"/# loadBalancerIP: "34.168.131.83"/' "$KUBE_DEST_DIR/traefik/values.yaml"
sed -i.bak 's/type: LoadBalancer/type: ClusterIP/g' "$KUBE_DEST_DIR/traefik/values.yaml"
# Configure Traefik to use host ports for KIND
cat >> "$KUBE_DEST_DIR/traefik/values.yaml" << 'EOF'

# Configure Traefik for KIND with host ports
deployment:
  kind: DaemonSet

ports:
  web:
    hostPort: 80
  websecure:
    hostPort: 443
EOF
find "$KUBE_DEST_DIR/traefik" -type f -name "*.bak" -delete


# 2. Create KIND cluster
info "Creating KIND cluster '$KIND_CLUSTER_NAME'ப்பாக..."
if ! kind get clusters | grep -q "$KIND_CLUSTER_NAME"; then
  kind create cluster --name "$KIND_CLUSTER_NAME" --config="$LOCAL_DEV_DIR/kind-config.yaml"
else
  info "KIND cluster '$KIND_CLUSTER_NAME' already exists."
fi

# 3. Install local-path-provisioner
info "Installing local-path-provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
info "Waiting for local-path-provisioner to be ready..."
kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n local-path-storage --timeout=120s

info "Configuring Traefik to use local-path-provisioner..."
sed -i.bak 's/storageClass: standard-rwo/storageClass: local-path/g' "$KUBE_DEST_DIR/traefik/values.yaml"
sed -i.bak 's/name: traefik-data/name: traefik/g' "$KUBE_DEST_DIR/traefik/values.yaml"

# 4. Install Traefik
info "Installing Traefik ingress controller..."

helm upgrade --install traefik traefik/traefik \
  -f "$KUBE_DEST_DIR/traefik/values.yaml" \
  -f "$KUBE_DEST_DIR/traefik/values-crd.yaml" \
  --namespace=default --create-namespace

# Get Traefik ClusterIP and update certissuer.yaml
info "Configuring cert-manager ClusterIssuer with Traefik ClusterIP..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n default --timeout=120s
TRAEFIK_CLUSTER_IP=$(kubectl get svc -n default traefik -o jsonpath='{.spec.clusterIP}')
sed -i.bak "s/        Ingress:/        url: http:\/\/$TRAEFIK_CLUSTER_IP\n        Ingress:/g" "$KUBE_DEST_DIR/cert-manager/certissuer.yaml"

# Apply IngressRoutes immediately after Traefik is ready
info "Applying IngressRoutes for routing..."
kubectl apply -f "$KUBE_DEST_DIR/namespace.yaml"
kubectl apply -f "$KUBE_DEST_DIR/auth/ingress-traefik.yaml"
kubectl apply -f "$KUBE_DEST_DIR/traefik/main-service-ingress.yaml"



# 5. Install cert-manager
info "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
info "Waiting for cert-manager pods to be ready..."
kubectl wait --for=condition=ready pod -l 'app.kubernetes.io/instance=cert-manager' -n cert-manager --timeout=120s

info "Applying self-signed ClusterIssuer..."
kubectl apply -f "$KUBE_DEST_DIR/cert-manager/selfsigned-issuer.yaml"

info "Configuring Certificate to use self-signed issuer..."
sed -i.bak "s|letsencrypt-staging|selfsigned-issuer|g" "$KUBE_DEST_DIR/cert-manager/cert.yaml"

info "Applying TLS certificate for local development..."
kubectl apply -f "$KUBE_DEST_DIR/cert-manager/cert.yaml"

info "Waiting for certificate to be ready..."
kubectl wait --for=condition=ready certificate/spezistudyplatform-main-tls-cert -n spezistudyplatform --timeout=60s

info "Extracting certificate for local testing..."
kubectl get secret spezistudyplatform-main-tls-secret -n spezistudyplatform -o jsonpath='{.data.tls\.crt}' | base64 -d > "$LOCAL_DEV_DIR/local-dev.crt"


# 6. Install Keycloak
info "Installing Keycloak..."

helm upgrade --install keycloak bitnami/keycloak \
  -f "$KUBE_DEST_DIR/auth/keycloak/values.yaml" \
  --namespace=spezistudyplatform --create-namespace --wait

info "Waiting for Keycloak to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n spezistudyplatform --timeout=300s

info "Bootstrapping Keycloak realm and clients..."
LOCAL_DEV_MODE=1 ansible-playbook ansible/bootstrap-keycloak.yaml

info "Applying oauth2-proxy secret..."
kubectl apply -f "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-secret.yaml"

info "Installing oauth2-proxy..."
helm upgrade --install oauth2-proxy oauth2-proxy/oauth2-proxy \
  -n spezistudyplatform -f "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-values.yaml" \
  --create-namespace --wait


# 7. Install CloudNativePG Operator
info "Installing CloudNativePG operator..."
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml
info "Waiting for CloudNativePG operator to be ready..."
RETRIES=5
DELAY=5
while [ $RETRIES -gt 0 ]; do
  if kubectl get pod -l app.kubernetes.io/name=cloudnative-pg -n cnpg-system > /dev/null 2>&1; then
    break
  fi
  echo "Waiting for operator pods to be created..."
  sleep $DELAY
  RETRIES=$((RETRIES-1))
done

if [ $RETRIES -eq 0 ]; then
  echo "Error: Timed out waiting for operator pods to be created."
  exit 1
fi

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg -n cnpg-system --timeout=120s


# 8. Apply Kubernetes manifests
info "Applying application manifests..."
kubectl apply -f "$KUBE_DEST_DIR/namespace.yaml"

# Explicitly apply critical secrets first to ensure they exist
info "Applying oauth2-proxy secret..."
kubectl apply -f "$KUBE_DEST_DIR/auth/oauth2-proxy/oauth2proxy-secret.yaml"

# Apply all other manifests
find "$KUBE_DEST_DIR" -type f -name "*.yaml" ! -name "*values.yaml" ! -path "*/tf/*" -exec grep -q "apiVersion:" {} \; -exec kubectl apply -f {} \;

info "Waiting for TLS certificate to be ready..."
kubectl wait --for=condition=ready certificate/spezistudyplatform-main-tls-cert -n spezistudyplatform --timeout=300s

info "Local environment setup is complete!"
info "Access services at https://$LOCAL_DOMAIN"
info "Traefik dashboard: http://localhost/dashboard/"
