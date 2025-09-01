{
  withConfig(config)::
    if config.externalSecrets.enabled then
      (if config.externalSecrets.provider == 'vault' then {
        // HashiCorp Vault for development
        vault: {
          apiVersion: 'v1',
          kind: 'Namespace',
          metadata: {
            name: 'vault',
          },
        },
        
        'vault-server': {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          metadata: {
            name: 'vault',
            namespace: 'vault',
            labels: {
              app: 'vault',
            },
          },
          spec: {
            replicas: 1,
            selector: {
              matchLabels: {
                app: 'vault',
              },
            },
            template: {
              metadata: {
                labels: {
                  app: 'vault',
                },
              },
              spec: {
                containers: [
                  {
                    name: 'vault',
                    image: 'hashicorp/vault:1.15',
                    args: [
                      'vault',
                      'server',
                      '-dev',
                      '-dev-root-token-id=' + config.externalSecrets.vault.rootToken,
                      '-dev-listen-address=0.0.0.0:8200',
                    ],
                    ports: [
                      {
                        containerPort: 8200,
                        name: 'vault',
                      },
                    ],
                    env: [
                      {
                        name: 'VAULT_DEV_ROOT_TOKEN_ID',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                    resources: {
                      limits: {
                        memory: '256Mi',
                        cpu: '250m',
                      },
                      requests: {
                        memory: '64Mi',
                        cpu: '50m',
                      },
                    },
                  },
                ],
              },
            },
          },
        },
        
        'vault-service': {
          apiVersion: 'v1',
          kind: 'Service',
          metadata: {
            name: 'vault',
            namespace: 'vault',
          },
          spec: {
            selector: {
              app: 'vault',
            },
            ports: [
              {
                port: 8200,
                targetPort: 8200,
                name: 'vault',
              },
            ],
          },
        },

        // Test secret in Vault (this would normally be done via vault CLI)
        'vault-backend-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-backend-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && vault kv put secret/spezistudyplatform-backend OAUTH_CLIENT_SECRET=Tmd2RUFQcFJaTzA5MENWcDEybHdNUDFyVzVDcTdJQ2EK || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        'vault-frontend-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-frontend-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && vault kv put secret/spezistudyplatform-frontend OAUTH_CLIENT_SECRET=dummy-frontend-secret || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        'vault-db-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-db-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && vault kv put secret/spezistudyplatform-postgres-credentials username=spezistudyplatform password=spezistudyplatform1!2@ || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        'vault-oauth2-proxy-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-oauth2-proxy-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && vault kv put secret/oauth2-proxy-secret client-id=oauth2-proxy client-secret=c4h7rptpKNYyHOpuH780CXEGyLvYmo6A cookie-secret=local-dev-cookie-secret-32-chars || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        // ClusterSecretStore for Vault
        'vault-secret-store': {
          apiVersion: 'external-secrets.io/v1',
          kind: 'ClusterSecretStore',
          metadata: {
            name: 'vault-backend',
          },
          spec: {
            provider: {
              vault: {
                server: config.externalSecrets.vault.server,
                path: 'secret',
                version: 'v2',
                auth: {
                  tokenSecretRef: {
                    name: 'vault-token',
                    namespace: 'external-secrets-system',
                    key: 'token',
                  },
                },
              },
            },
          },
        },

        // Token secret for Vault authentication
        'vault-token-secret': {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: 'vault-token',
            namespace: 'external-secrets-system',
          },
          type: 'Opaque',
          data: {
            token: std.base64(config.externalSecrets.vault.rootToken),
          },
        },

        
      } else if config.externalSecrets.provider == 'gcpsm' then {
        // GCP Secret Manager for production
        'gcp-secret-store': {
          apiVersion: 'external-secrets.io/v1',
          kind: 'ClusterSecretStore',
          metadata: {
            name: 'gcpsm-secret-store',
          },
          spec: {
            provider: {
              gcpsm: {
                projectID: config.externalSecrets.gcp.projectId,
                auth: {
                  secretRef: {
                    secretAccessKeySecretRef: {
                      name: config.externalSecrets.gcp.serviceAccountKeySecret,
                      namespace: 'external-secrets-system',
                      key: 'secret-access-credentials',
                    },
                  },
                },
              },
            },
          },
        },

        // Password generators for automatic secret creation
        'oauth-secret-generator': {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          metadata: {
            name: 'oauth-secret-generator',
            namespace: 'external-secrets-system',
          },
          spec: {
            length: 32,
            digits: 5,
            symbols: 5,
            symbolCharacters: '-_$@',
            noUpper: false,
            allowRepeat: true,
          },
        },

        'db-password-generator': {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          metadata: {
            name: 'db-password-generator',
            namespace: 'external-secrets-system',
          },
          spec: {
            length: 20,
            digits: 3,
            symbols: 3,
            symbolCharacters: '!@#$',
            noUpper: false,
            allowRepeat: true,
          },
        },

        'cookie-secret-generator': {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          metadata: {
            name: 'cookie-secret-generator',
            namespace: 'external-secrets-system',
          },
          spec: {
            length: 32,
            digits: 0,
            symbols: 0,
            noUpper: false,
            allowRepeat: true,
          },
        },
        
      } else {})
    else {}
}