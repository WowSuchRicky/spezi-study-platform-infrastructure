
function(config) 
  // Parse YAML documents separated by ---
  local yamlContent = importstr "https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml";
  local docs = std.split(yamlContent, '\n---');
  local validDocs = [
    std.parseYaml(doc)
    for doc in docs
    if std.length(std.stripChars(doc, ' \t\n')) > 0 && !std.startsWith(std.stripChars(doc, ' \t\n'), '#')
  ];

// Convert the list items to individual named resources for ArgoCD
local namedDocs = {
  [std.strReplace(std.strReplace(doc.metadata.name, '-', '_'), '.', '_')]: doc {
    metadata+: {
      annotations+: {
        "argocd.argoproj.io/sync-wave": "1",
      },
    },
  }
  for doc in validDocs
  if std.objectHas(doc, 'metadata') && std.objectHas(doc.metadata, 'name')
};

namedDocs + {
  "cert-manager-config": {
    "cluster-issuer": {
      apiVersion: "cert-manager.io/v1",
      kind: "ClusterIssuer",
      metadata: {
        name: config.infrastructure.tls.issuer,
        annotations: {
          "argocd.argoproj.io/sync-wave": "1",
        },
      },
      spec: if config.infrastructure.tls.selfSigned then {
        selfSigned: {},
      } else {
        acme: {
          server: if config.infrastructure.tls.staging then "https://acme-staging-v02.api.letsencrypt.org/directory" else "https://acme-v02.api.letsencrypt.org/directory",
          email: "spam@muci.sh",
          privateKeySecretRef: {
            name: config.infrastructure.tls.issuer,
          },
          solvers: [
            {
              http01: {
                ingress: {
                  class: config.infrastructure.cluster.ingressClass,
                },
              },
            },
          ],
        },
      },
    },
    "platform-certificate": {
      apiVersion: "cert-manager.io/v1",
      kind: "Certificate",
      metadata: {
        name: "spezistudyplatform-main-tls-cert",
        namespace: config.project.namespace,
        annotations: {
          "argocd.argoproj.io/sync-wave": "1",
        },
      },
      spec: {
        commonName: config.domains.primary,
        secretName: "spezistudyplatform-main-tls-secret",
        issuerRef: {
          name: config.infrastructure.tls.issuer,
          kind: "ClusterIssuer",
        },
        dnsNames: [
          config.domains.primary,
        ],
      },
    },
  },
}
