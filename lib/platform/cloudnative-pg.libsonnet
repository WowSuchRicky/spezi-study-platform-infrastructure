{
  local k = import 'k.libsonnet',
  withConfig(config)::
    std.objectValues(
      (let
        cnpgOperator = std.native('parseYaml')(importstr '../../vendor/cloudnative-pg/cnpg-1.27.0.yaml')
      in
      {
        [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
        for resource in cnpgOperator
        if resource.kind != 'CustomResourceDefinition'
      }) + {
        postgres_cluster: {
          apiVersion: 'postgresql.cnpg.io/v1',
          kind: 'Cluster',
          metadata: {
            name: 'spezistudyplatform-db',
            namespace: config.namespace,
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
    ),
}