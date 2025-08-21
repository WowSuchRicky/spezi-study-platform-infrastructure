function(config) 
{
  'cloudnative-pg-install': {
    apiVersion: 'v1',
    kind: 'List',
    metadata: {
      annotations: {
        "argocd.argoproj.io/sync-wave": "2",
      },
    },
    items: std.parseYaml(importstr 'cloudnative-pg/cnpg-1.17.5.yaml'),
  },

  'postgres-cluster': {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'Cluster',
    metadata: {
      name: config.project.name + '-db',
      namespace: config.project.namespace,
      annotations: {
        "argocd.argoproj.io/sync-wave": "2",
      },
    },
    spec: {
      imageName: 'ghcr.io/cloudnative-pg/postgresql:17-bullseye',
      instances: 1,
      storage: {
        size: '1Gi',
      },
      monitoring: {
        enablePodMonitor: config.infrastructure.database.enablePodMonitor,
      },
      enableSuperuserAccess: true,
      bootstrap:
        {
          initdb:
            {
              database: config.project.name,
              owner: config.project.name,
              secret:
                {
                  name: config.project.name + '-postgres-credentials',
                },
            },
        },
    },
  },
}