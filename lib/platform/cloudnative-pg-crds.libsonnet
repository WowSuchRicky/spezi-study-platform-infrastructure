local k = import 'k.libsonnet';

{
  withConfig(config)::
    std.objectValues({
      local cnpgManifests = std.native('parseYaml')(importstr '../../vendor/cloudnative-pg/cnpg-1.27.0.yaml');
      
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in cnpgManifests
      if resource.kind == 'CustomResourceDefinition'
    }),
}