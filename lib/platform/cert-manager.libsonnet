{
  withConfig(config)::
    local certManagerUrl = 'https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml';
    local certManagerManifests = std.native('manifestYamlFromUrl')(certManagerUrl);
    // Convert to array if it's an object, otherwise use as is
    local manifestArray = if std.isArray(certManagerManifests) then certManagerManifests else std.objectValues(certManagerManifests);
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
      for resource in manifestArray
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in processedManifests
    },
}