# Keycloak Google Identity Provider Configuration

# Google Identity Provider for Keycloak
resource "keycloak_oidc_identity_provider" "google" {
  realm             = keycloak_realm.realm.id
  alias             = "google"
  display_name      = "Google"
  provider_id       = "google"
  
  client_id         = data.google_secret_manager_secret_version.google_sso_client_id.secret_data
  client_secret     = data.google_secret_manager_secret_version.google_sso_client_secret.secret_data
  
  authorization_url = "https://accounts.google.com/oauth2/v2/auth"
  token_url         = "https://oauth2.googleapis.com/token"
  user_info_url     = "https://openidconnect.googleapis.com/v1/userinfo"
  jwks_url          = "https://www.googleapis.com/oauth2/v3/certs"
  issuer            = "https://accounts.google.com"
  
  # Enable automatic account creation
  store_token                 = false
  add_read_token_role_on_create = false
  authenticate_by_default     = false
  enabled                     = true
  trust_email                 = true
  link_only                   = false
  
  # Default scopes for Google
  default_scopes = "openid email profile"
  
  # Import existing user if email matches
  first_broker_login_flow_alias = "first broker login"
  sync_mode = "IMPORT"
}

# Identity Provider Mapper for email
resource "keycloak_custom_identity_provider_mapper" "google_email_mapper" {
  realm                    = keycloak_realm.realm.id
  name                     = "email-mapper"
  identity_provider_alias  = keycloak_oidc_identity_provider.google.alias
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  
  extra_config = {
    "syncMode" = "INHERIT"
    "user.attribute" = "email"
    "claim" = "email"
  }
}

# Identity Provider Mapper for first name
resource "keycloak_custom_identity_provider_mapper" "google_first_name_mapper" {
  realm                    = keycloak_realm.realm.id
  name                     = "first-name-mapper"
  identity_provider_alias  = keycloak_oidc_identity_provider.google.alias
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  
  extra_config = {
    "syncMode" = "INHERIT"
    "user.attribute" = "firstName"
    "claim" = "given_name"
  }
}

# Identity Provider Mapper for last name
resource "keycloak_custom_identity_provider_mapper" "google_last_name_mapper" {
  realm                    = keycloak_realm.realm.id
  name                     = "last-name-mapper"
  identity_provider_alias  = keycloak_oidc_identity_provider.google.alias
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"
  
  extra_config = {
    "syncMode" = "INHERIT"
    "user.attribute" = "lastName"
    "claim" = "family_name"
  }
}

# Identity Provider Mapper for username (use email as username)
resource "keycloak_custom_identity_provider_mapper" "google_username_mapper" {
  realm                    = keycloak_realm.realm.id
  name                     = "username-mapper"
  identity_provider_alias  = keycloak_oidc_identity_provider.google.alias
  identity_provider_mapper = "oidc-username-idp-mapper"
  
  extra_config = {
    "syncMode" = "INHERIT"
    "template" = "$${CLAIM.email}"
  }
}

# Identity Provider Mapper for email_verified (maps provider claim into Keycloak user.emailVerified)
resource "keycloak_custom_identity_provider_mapper" "google_email_verified_mapper" {
  realm                    = keycloak_realm.realm.id
  name                     = "email-verified-mapper"
  identity_provider_alias  = keycloak_oidc_identity_provider.google.alias
  identity_provider_mapper = "oidc-user-attribute-idp-mapper"

  extra_config = {
    "syncMode" = "INHERIT"
    # Map the OIDC claim 'email_verified' from Google into the Keycloak user property
    "user.attribute" = "emailVerified"
    "claim" = "email_verified"
  }
}


