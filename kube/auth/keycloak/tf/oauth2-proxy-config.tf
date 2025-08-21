resource "keycloak_realm" "realm" {
  realm   = "spezistudyplatform"
  enabled = true
}


# configured per: https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc 
resource "keycloak_openid_client" "oauth2_proxy_client" {
  realm_id            = keycloak_realm.realm.id
  client_id           = "oauth2-proxy"

  name                = "oauth2-proxy"
  enabled             = true

  access_type         = "CONFIDENTIAL"
  valid_redirect_uris = [
    "https://platform.spezi.stanford.edu/oauth2/callback"
  ]

  direct_access_grants_enabled = false 
  standard_flow_enabled        = true
}

# Create groups client scope
resource "keycloak_openid_client_scope" "groups_scope" {
  realm_id    = keycloak_realm.realm.id
  name        = "groups"
  description = "Groups membership"
}

# Add groups scope mapper for OAuth2-proxy
resource "keycloak_openid_group_membership_protocol_mapper" "oauth2_proxy_groups_mapper" {
  realm_id         = keycloak_realm.realm.id
  client_scope_id  = keycloak_openid_client_scope.groups_scope.id
  name             = "groups"

  claim_name     = "groups"
  full_path      = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Add roles mapper to groups scope (OAuth2-proxy checks roles in groups claim)
resource "keycloak_openid_user_realm_role_protocol_mapper" "oauth2_proxy_roles_mapper" {
  realm_id         = keycloak_realm.realm.id
  client_scope_id  = keycloak_openid_client_scope.groups_scope.id
  name             = "realm roles"

  claim_name                = "groups"
  multivalued               = true
  add_to_id_token          = true
  add_to_access_token      = true
  add_to_userinfo          = true
}

# Assign groups scope to oauth2-proxy client
resource "keycloak_openid_client_optional_scopes" "oauth2_proxy_groups_scope" {
  realm_id  = keycloak_realm.realm.id
  client_id = keycloak_openid_client.oauth2_proxy_client.id
  optional_scopes = [
    keycloak_openid_client_scope.groups_scope.name,
  ]
}

# Create required role for OAuth2-proxy authorization
resource "keycloak_role" "authorized_users" {
  realm_id    = keycloak_realm.realm.id
  name        = "spezistudyplatform-authorized-users"
  description = "Users authorized to access the Spezi Study Platform"
}

# Note: User creation for production should be done through proper user management processes
# The following users are examples for local development only and should not be deployed to production

# Test user 1 - authorized user
resource "keycloak_user" "testuser" {
  realm_id = keycloak_realm.realm.id
  username = "testuser"
  email    = "testuser@example.com"
  email_verified = true
  
  first_name = "Test"
  last_name  = "User"
  
  initial_password {
    value     = "password123"
    temporary = false
  }
}

# Test user 2 - unauthorized user  
resource "keycloak_user" "testuser2" {
  realm_id = keycloak_realm.realm.id
  username = "testuser2"
  email    = "testuser2@example.com"
  email_verified = true
  
  first_name = "Test"
  last_name  = "User2"
  
  initial_password {
    value     = "password456"
    temporary = false
  }
}

# Assign authorized role to testuser
resource "keycloak_user_roles" "testuser_roles" {
  realm_id = keycloak_realm.realm.id
  user_id  = keycloak_user.testuser.id
  
  role_ids = [
    keycloak_role.authorized_users.id
  ]
}

# Note: testuser2 intentionally does not get the authorized role