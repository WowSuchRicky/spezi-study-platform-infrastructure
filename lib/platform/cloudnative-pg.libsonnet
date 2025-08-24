{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local cnpgManifests = kustomize.build('../../vendor/cloudnative-pg/');
    // Convert to array if it's an object, otherwise use as is
    local manifestArray = if std.isArray(cnpgManifests) then cnpgManifests else std.objectValues(cnpgManifests);
    local filtered = [
      resource
      for resource in manifestArray
      if resource.kind != 'CustomResourceDefinition'
    ];
    local allManifests = filtered + [
      {
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
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in allManifests
    },
}