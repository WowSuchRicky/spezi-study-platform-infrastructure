terraform {
  backend "gcs" {
    bucket  = "spezistudyplatform-tf-state-prod"
    prefix  = "terraform/state/kube-manifests"
  }
}