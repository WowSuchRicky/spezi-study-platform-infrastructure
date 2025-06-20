terraform {
  backend "gcs" {
    bucket  = "spezistudyplatform-tf-state-prod"
    prefix  = "terraform/state/gke"
  }
}