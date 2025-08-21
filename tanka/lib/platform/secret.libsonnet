
function(config) {
  local secret = self;

  {
    postgresCredentials(config)::
      if config.features.sealedSecrets then
        {
          apiVersion: 'bitnami.com/v1alpha1',
          kind: 'SealedSecret',
          metadata: {
            name: config.project.name + '-postgres-credentials',
            namespace: config.project.namespace,
          },
          spec: {
            encryptedData: {
              username: 'TODO_ENCRYPTED_USERNAME', // Placeholder
              password: 'TODO_ENCRYPTED_PASSWORD', // Placeholder
            },
            template: {
              metadata: {
                name: config.project.name + '-postgres-credentials',
                namespace: config.project.namespace,
              },
              type: 'Opaque',
            },
          },
        }
      else
        {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: config.project.name + '-postgres-credentials',
            namespace: config.project.namespace,
          },
          type: 'Opaque',
          stringData: {
            username: config.project.name, // Use project name as username for local-dev
            password: 'password', // Simple password for local-dev
          },
        },

    backendSecrets(config)::
      if config.features.sealedSecrets then
        {
          apiVersion: 'bitnami.com/v1alpha1',
          kind: 'SealedSecret',
          metadata: {
            name: config.project.name + '-backend-secret',
            namespace: config.project.namespace,
          },
          spec: {
            encryptedData: {
              OAUTH_CLIENT_SECRET: 'TODO_ENCRYPTED_OAUTH_CLIENT_SECRET', // Placeholder
            },
            template: {
              metadata: {
                name: config.project.name + '-backend-secret',
                namespace: config.project.namespace,
              },
              type: 'Opaque',
            },
          },
        }
      else
        {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: config.project.name + '-backend-secret',
            namespace: config.project.namespace,
          },
          type: 'Opaque',
          stringData: {
            OAUTH_CLIENT_SECRET: 'local-dev-secret', // Simple secret for local-dev
          },
        },

    frontendSecrets(config)::
      if config.features.sealedSecrets then
        {
          apiVersion: 'bitnami.com/v1alpha1',
          kind: 'SealedSecret',
          metadata: {
            name: config.project.name + '-frontend-secret',
            namespace: config.project.namespace,
          },
          spec: {
            encryptedData: {
              OAUTH_CLIENT_SECRET: 'TODO_ENCRYPTED_OAUTH_CLIENT_SECRET', // Placeholder
            },
            template: {
              metadata: {
                name: config.project.name + '-frontend-secret',
                namespace: config.project.namespace,
              },
              type: 'Opaque',
            },
          },
        }
      else
        {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: config.project.name + '-frontend-secret',
            namespace: config.project.namespace,
          },
          type: 'Opaque',
          stringData: {
            OAUTH_CLIENT_SECRET: 'local-dev-secret', // Simple secret for local-dev
          },
        },
  }
}
