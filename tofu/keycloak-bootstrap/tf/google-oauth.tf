# Google OAuth Configuration
# This creates a Google OAuth client automatically using external provider

# Create OAuth consent screen
resource "null_resource" "oauth_consent_screen" {
  provisioner "local-exec" {
    command = <<-EOT
      # Check if consent screen already exists
      if ! gcloud alpha iap oauth-brands list --project=${var.gcp_project_id} --format="value(name)" | grep -q .; then
        # Create OAuth consent screen
        gcloud alpha iap oauth-brands create \
          --application_title="Spezi Study Platform" \
          --support_email="support@spezi.stanford.edu" \
          --project=${var.gcp_project_id}
      fi
    EOT
  }
}

# Create OAuth client
resource "null_resource" "google_oauth_client" {
  depends_on = [null_resource.oauth_consent_screen]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Create OAuth client and capture output
      OAUTH_OUTPUT=$(gcloud alpha iap oauth-clients create \
        --brand=$(gcloud alpha iap oauth-brands list --project=${var.gcp_project_id} --format="value(name)") \
        --display_name="Spezi Study Platform - Keycloak" \
        --project=${var.gcp_project_id} \
        --format="value(name,secret)")
      
      # Extract client ID and secret
      CLIENT_NAME=$(echo "$OAUTH_OUTPUT" | cut -d' ' -f1)
      CLIENT_SECRET=$(echo "$OAUTH_OUTPUT" | cut -d' ' -f2)
      CLIENT_ID=$(basename "$CLIENT_NAME")
      
      # Store in Secret Manager
      echo "$CLIENT_ID" | gcloud secrets create keycloak-google-client-id --data-file=- --project=${var.gcp_project_id} || \
        echo "$CLIENT_ID" | gcloud secrets versions add keycloak-google-client-id --data-file=- --project=${var.gcp_project_id}
      
      echo "$CLIENT_SECRET" | gcloud secrets create keycloak-google-client-secret --data-file=- --project=${var.gcp_project_id} || \
        echo "$CLIENT_SECRET" | gcloud secrets versions add keycloak-google-client-secret --data-file=- --project=${var.gcp_project_id}
      
      # Store client ID in terraform state for output
      echo "$CLIENT_ID" > /tmp/google_oauth_client_id.txt
    EOT
  }
}

# Secret Manager secrets (will be populated by the script above)
resource "google_secret_manager_secret" "google_client_id" {
  project   = var.gcp_project_id
  secret_id = "keycloak-google-client-id"
  
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "google_client_secret" {
  project   = var.gcp_project_id
  secret_id = "keycloak-google-client-secret"
  
  replication {
    auto {}
  }
}

# Data source to read the generated client ID
data "local_file" "google_oauth_client_id" {
  depends_on = [null_resource.google_oauth_client]
  filename   = "/tmp/google_oauth_client_id.txt"
}

# Output the client ID
output "google_oauth_client_id" {
  description = "Google OAuth Client ID"
  value       = trimspace(data.local_file.google_oauth_client_id.content)
  depends_on  = [null_resource.google_oauth_client]
}