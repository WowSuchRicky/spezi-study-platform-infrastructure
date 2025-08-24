function(component=null)
  // Local development environment configuration
  local config = (import '../../lib/platform/config.libsonnet').localDev;
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
  local kustomize = tanka.kustomize.new(std.thisFile);
  local namespace = import '../../lib/platform/namespace.libsonnet';
  local certManager = import '../../lib/platform/cert-manager.libsonnet';
  local cloudnativePgCrds = import '../../lib/platform/cloudnative-pg-crds.libsonnet';
  local cloudnativePg = import '../../lib/platform/cloudnative-pg.libsonnet';
  local backend = import '../../lib/platform/backend.libsonnet';
  local frontend = import '../../lib/platform/frontend.libsonnet';
  local keycloak = import '../../lib/platform/keycloak.libsonnet';
  local oauth2Proxy = import '../../lib/platform/oauth2-proxy.libsonnet';
  local traefik = import '../../lib/platform/traefik.libsonnet';
  // Note: argocd-apps is not included here, it's used to generate the apps that point to this env.

  local components = {
    namespace: namespace.withConfig(config),
    'cert-manager': certManager.withConfig(config),
    'cloudnative-pg-crds': cloudnativePgCrds.withConfig(config),
    'cloudnative-pg': cloudnativePg.withConfig(config),
    'sealed-secrets': kustomize.build(path='sealed-secrets'),
    backend: backend.withConfig(config),
    frontend: frontend.withConfig(config),
    keycloak: keycloak.withConfig(config),
    'oauth2-proxy': oauth2Proxy.withConfig(config),
    traefik: traefik.withConfig(config),
  };

  if component != null then
    if std.objectHas(components, component) then
      components[component]
    else
      error 'Component "' + component + '" not found. Available components: ' + std.join(', ', std.objectFields(components))
  else
    // If no component is specified, render all of them.
    std.foldl(function(a, b) a + b, std.objectValues(components), {})
