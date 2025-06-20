variable "keycloak_client_id" {
  description = "Keycloak client ID"
  type        = string
  default     = "admin-cli"
}

variable "keycloak_username" {
  description = "Keycloak username"
  type        = string
  default     = "user"
}

variable "keycloak_password" {
  description = "Keycloak password"
  type        = string
  sensitive   = true
}

variable "keycloak_url" {
  description = "Keycloak base URL"
  type        = string
  default     = "https://study.muci.sh/auth"
}
