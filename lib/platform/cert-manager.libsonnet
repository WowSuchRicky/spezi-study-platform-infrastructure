local k = import 'k.libsonnet';

{
  withConfig(config)::
    std.objectValues(
      let
        certManagerManifests = std.native('parseYaml')(importstr '../../vendor/cert-manager/cert-manager.yaml')
      in
        {
          [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]:
            if resource.kind == 'Deployment' && resource.metadata.name == 'cert-manager' then
              resource + {
                spec+: {
                  template+: {
                    spec+: {
                      containers: [
                        if container.name == 'cert-manager' then
                          container + {
                            args: container.args + ['--leader-election-namespace=cert-manager']
                          }
                        else container
                        for container in resource.spec.template.spec.containers
                      ]
                    }
                  }
                }
              }
            else resource
          for resource in certManagerManifests
        }
    )
}