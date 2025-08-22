{
  withConfig(config)::
    let
      app(name, wave) = {
        apiVersion: 'argoproj.io/v1alpha1',
        kind: 'Application',
        metadata: {
          name: 'local-dev-' + name,
          namespace: 'argocd',
          annotations: {
            'argocd.argoproj.io/sync-wave': std.toString(wave),
          },
        },
        spec: {
          project: 'default',
          source: {
            repoURL: 'https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git',
            path: 'environments/local-dev',
            targetRevision: 'jsonnet-working',
            jsonnet: {
              tlas: [
                {
                  name: 'component',
                  value: name,
                },
              ],
            },
          },
          destination: {
            server: 'https://kubernetes.default.svc',
            namespace: config.namespace,
          },
          syncPolicy: {
            automated: {
              prune: true,
              selfHeal: true,
            },
            syncOptions: [
              'CreateNamespace=true',
            ],
          },
        },
      },
      apps = {
        // Wave 0
        'namespace-app': app('namespace', 0),
        'cnpg-crds-app': app('cloudnative-pg-crds', 0),

        // Wave 1
        'traefik-app': app('traefik', 1),
        'cert-manager-app': app('cert-manager', 1),

        // Wave 2
        'oauth2-proxy-app': app('oauth2-proxy', 2),
        'keycloak-app': app('keycloak', 2),
        'cnpg-app': app('cloudnative-pg', 2),

        // Wave 3
        'backend-app': app('backend', 3),
        'frontend-app': app('frontend', 3),
      }
    in
      std.objectValues(apps),
}
