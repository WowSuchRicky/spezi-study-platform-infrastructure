terraform {
  backend "gcs" {
    # bucket and prefix are provided via backend-config from Ansible
  }
}