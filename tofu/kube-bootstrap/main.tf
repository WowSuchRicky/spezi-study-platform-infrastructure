provider "kubernetes" {
  config_path    = var.kubernetes_config_path
  config_context = var.kubernetes_config_context
}

data "kubernetes_all_namespaces" "all" {}

locals {
  manifest_files = flatten([
      for file in fileset(".", "../../**/*.{yml,yaml,json}") : 
      "${file}"
      if !endswith(file, "_secret.yaml") && 
         !endswith(file, "secrets.yaml") &&
         !endswith(file, "values.yaml") &&
         !strcontains(file, "github") &&
         (endswith(file, ".yml") || 
          endswith(file, ".yaml") ||
          endswith(file, "secrets.json") ||
          endswith(file, "secret.json"))
  ])

  manifests = flatten([
    for file in local.manifest_files : [
      for doc in split("---", file("${file}")) :
      {
        content  = doc
        filename = file
      }
      if trimspace(doc) != ""
    ]
  ])
}

resource "kubernetes_manifest" "manifests" {
  for_each = { for idx, manifest in local.manifests : "${manifest.filename}-${idx}" => manifest }
  
  manifest = try(
    yamldecode(each.value.content),
    jsondecode(each.value.content),
    null
  )

  lifecycle {
    precondition {
      condition     = try(yamldecode(each.value.content), jsondecode(each.value.content), false) != false
      error_message = "Failed to parse manifest from file: ${each.value.filename}"
    }
  }
}


# Add this to outputs.tf
output "processed_files" {
  description = "List of processed manifest files"
  value       = distinct([for m in local.manifests : m.filename])
}

output "failed_files" {
  description = "List of files that failed to parse"
  value = [
    for key, manifest in kubernetes_manifest.manifests :
    manifest.manifest == null ? split("-", key)[0] : null
  ]
}