variable "kubernetes_config_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubernetes_config_context" {
  description = "Context to use from the kubeconfig file"
  type        = string
  default     = ""
}

variable "manifest_paths" {
  description = "List of paths to Kubernetes manifest files or directories"
  type        = list(string)
  default     = ["./manifests"]
}