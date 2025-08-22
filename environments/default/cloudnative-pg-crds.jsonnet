local k = import '../lib/k.libsonnet';

// Import the CloudNative-PG operator manifests and filter for CRDs only
local cnpgManifests = std.native('parseYaml')(importstr '../../vendor/cloudnative-pg/cnpg-1.27.0.yaml');

{
  // Include only CRDs
  [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
  for resource in cnpgManifests
  if resource.kind == 'CustomResourceDefinition'
}