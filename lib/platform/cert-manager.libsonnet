{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local certManagerManifests = kustomize.build('../../vendor/cert-manager/');
    local processedManifests = [
      if resource.kind == 'Deployment' && resource.metadata.name == 'cert-manager' then
        resource + {
          spec+: {
            template+: {
              spec+: {
                containers: [
                  if container.name == 'cert-manager' then
                    container + {
                      args: container.args + ['--leader-election-namespace=cert-manager'],
                    }
                  else container
                  for container in resource.spec.template.spec.containers
                ],
              },
            },
          },
        }
      else resource
      for resource in certManagerManifests
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in processedManifests
    },
}