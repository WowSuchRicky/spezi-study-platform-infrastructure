// tanka/lib/platform/argocd-apps.libsonnet
function(config) 
  local components = [
    'namespace',
    'cert-manager',
    'cloudnative-pg',
    'keycloak',
    'oauth2-proxy',
    'backend',
    'frontend',
    'traefik',
  ];

  {
    [component + '-app']: {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'Application',
      metadata: {
        name: config.project.name + '-' + component,
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave':
            if component == 'namespace' then '0'
            else if component == 'cert-manager' then '1'
            else if component == 'cloudnative-pg' then '2'
            else if component == 'keycloak' then '3'
            else if component == 'oauth2-proxy' then '4'
            else if component == 'backend' then '5'
            else if component == 'frontend' then '6'
            else if component == 'traefik' then '7'
            else error 'Unknown component: ' + component,
        },
      },
      spec: {
        project: 'default',
        source: {
          repoURL: 'https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git',
          targetRevision: 'main',
          path: 'tanka/environments/' + config.environment.name,
          directory: {
            jsonnet: {
              extVars: [
                {
                  name: 'LOCAL_IP',
                  value: config.domains.primary,
                },
              ],
            },
            include: component + '.jsonnet',
          },
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: if component == 'namespace' then config.project.namespace
                    else if component == 'cert-manager' then 'cert-manager'
                    else config.project.namespace,
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
    }
    for component in components
  }