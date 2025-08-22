local k = import '../lib/k.libsonnet';

// Import the cert-manager manifests
local certManagerManifests = std.native('parseYaml')(importstr '../../vendor/cert-manager/cert-manager.yaml');

{
  // Include all cert-manager components with leader election namespace configuration
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