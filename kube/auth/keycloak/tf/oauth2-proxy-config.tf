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
    "https://study.muci.sh/oauth2/callback"
  ]

  direct_access_grants_enabled = false 
  standard_flow_enabled        = true

  login_theme = "keycloakify-starter"
}