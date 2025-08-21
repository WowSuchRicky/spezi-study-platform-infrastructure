// Parse cert-manager YAML from remote URL
local yamlContent = importstr "https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml";
local docs = std.split(yamlContent, '\n---');

// Parse all YAML documents, skipping empty ones
local parsedDocs = [
  std.parseYaml(doc)
  for doc in docs
  if std.length(std.stripChars(doc, ' \t\n')) > 0 && !std.startsWith(std.stripChars(doc, ' \t\n'), '#')
];

// Convert to array of resources for ArgoCD
[
  doc {
    metadata+: {
      annotations+: {
        "argocd.argoproj.io/sync-wave": "1",
      },
    },
  }
  for doc in parsedDocs
  if std.objectHas(doc, 'metadata') && std.objectHas(doc.metadata, 'name')
]