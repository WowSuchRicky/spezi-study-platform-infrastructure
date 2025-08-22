local k = import '../lib/k.libsonnet';

// Import the CloudNative-PG operator manifests
local cnpgOperator = std.native('parseYaml')(importstr '../../vendor/cloudnative-pg/cnpg-1.27.0.yaml');

{
  // Include all CloudNative-PG operator components except CRDs
  [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
  for resource in cnpgOperator
  if resource.kind != 'CustomResourceDefinition'
} + {
  // Add our PostgreSQL cluster
  postgres_cluster: {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'Cluster',
    metadata: {
      name: 'spezistudyplatform-db',
      namespace: 'spezistudyplatform',
    },
    spec: {
      imageName: 'ghcr.io/cloudnative-pg/postgresql:17-bullseye',
      instances: 1,
      storage: {
        size: '1Gi',
      },
      monitoring: {
        enablePodMonitor: true,
      },
      enableSuperuserAccess: true,
      bootstrap: {
        initdb: {
          database: 'spezistudyplatform',
          owner: 'spezistudyplatform',
          secret: {
            name: 'spezistudyplatform-postgres-credentials',
          },
        },
      },
    },
  },
}