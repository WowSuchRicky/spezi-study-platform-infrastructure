# currently requires manual setup: https://registry.terraform.io/providers/mrparkers/keycloak/latest/docs
provider "keycloak" {
  client_id = var.keycloak_client_id
  username  = var.keycloak_username
  password  = var.keycloak_password
  url       = var.keycloak_url
}

terraform {
    required_providers {
        keycloak = {
            source = "mrparkers/keycloak"
            version = ">= 4.0.0"
        }
    }
}