{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local cnpgManifests = kustomize.build('../../vendor/cloudnative-pg/');
    [
      resource
      for resource in cnpgManifests
      if resource.kind == 'CustomResourceDefinition'
    ],
}