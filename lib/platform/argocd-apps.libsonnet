{
  local app(name, wave, config, envPath, envPrefix) = {
    apiVersion: 'argoproj.io/v1alpha1',
    kind: 'Application',
    metadata: {
      name: envPrefix + '-' + name,
      namespace: 'argocd',
      annotations: {
        'argocd.argoproj.io/sync-wave': std.toString(wave),
      },
    },
    spec: {
      project: 'default',
      source: {
        repoURL: 'https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git',
        path: envPath,
        targetRevision: 'convert-prod-env',
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
        server: if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'https://34.168.131.83' else 'https://kubernetes.default.svc',
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
    local envPath = if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'environments/default' else 'environments/local-dev';
    local envPrefix = if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'prod' else 'local-dev';
    std.objectValues({
      // Wave 0
      'namespace-app': app('namespace', 0, config, envPath, envPrefix),
      'cnpg-crds-app': app('cloudnative-pg-crds', 0, config, envPath, envPrefix),

      // Wave 1
      'traefik-app': app('traefik', 1, config, envPath, envPrefix),
      'cert-manager-app': app('cert-manager', 1, config, envPath, envPrefix),

      // Wave 2
      'cnpg-app': app('cloudnative-pg', 2, config, envPath, envPrefix),
      'auth-app': app('auth', 2, config, envPath, envPrefix),

      // Wave 3
      'backend-app': app('backend', 3, config, envPath, envPrefix),
      'frontend-app': app('frontend', 3, config, envPath, envPrefix),
    }),
}
