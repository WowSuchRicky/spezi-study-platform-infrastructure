{
  withConfig(config)::
    if config.externalSecrets.enabled then
      [
        // Example ExternalSecret for OAuth2 Proxy
        {
          apiVersion: 'external-secrets.io/v1beta1',
          kind: 'ExternalSecret',
          metadata: {
            name: 'oauth2-proxy-external-secret',
            namespace: config.platform.namespace,
            annotations: {
              'argocd.argoproj.io/sync-wave': '25',
            },
          },
          spec: {
            refreshInterval: '15s',
            secretStoreRef: {
              name: 'vault-backend',
              kind: 'ClusterSecretStore',
            },
            target: {
              name: 'oauth2-proxy-secret',
              creationPolicy: 'Owner',
            },
            data: [
              {
                secretKey: 'client-id',
                remoteRef: {
                  key: 'oauth2-proxy',
                  property: 'client-id',
                },
              },
              {
                secretKey: 'client-secret',
                remoteRef: {
                  key: 'oauth2-proxy',
                  property: 'client-secret',
                },
              },
              {
                secretKey: 'cookie-secret',
                remoteRef: {
                  key: 'oauth2-proxy',
                  property: 'cookie-secret',
                },
              },
            ],
          },
        },
      ]
    else []
}