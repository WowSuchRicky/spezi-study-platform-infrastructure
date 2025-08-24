{
  local app(name, wave, config) = {
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
        plugin: {
          name: 'tanka',
          env: [
            {
              name: 'COMPONENT',
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
          'ServerSideApply=true',
        ],
      },
    },
  },
  withConfig(config)::
    std.objectValues({
      // Wave 0
      'namespace-app': app('namespace', 0, config),
      'cnpg-crds-app': app('cloudnative-pg-crds', 0, config),

      // Wave 1
      'traefik-app': app('traefik', 1, config),
      'cert-manager-app': app('cert-manager', 1, config),

      // Wave 2
      'oauth2-proxy-app': app('oauth2-proxy', 2, config),
      'keycloak-app': app('keycloak', 2, config),
      'cnpg-app': app('cloudnative-pg', 2, config),

      // Wave 3
      'backend-app': app('backend', 3, config),
      'frontend-app': app('frontend', 3, config),
    }),
}
