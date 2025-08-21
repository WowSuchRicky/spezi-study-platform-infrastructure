
function(config) {
  "cert-manager": {
    apiVersion: "v1",
    kind: "List",
    metadata: {
      annotations: {
        "argocd.argoproj.io/sync-wave": "1",
      },
    },
    items: std.parseYaml(importstr "cert-manager/cert-manager.yaml"),
  },

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
