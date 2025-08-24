{
  apiVersion: 'tanka.dev/v1alpha1',
  kind: 'Environment',
  metadata: {
    name: 'environments/default',
  },
  spec: {
    namespace: 'default',
    contextNames: ['kind-spezi-study-platform'],
    resourceDefaults: {},
    expectVersions: {},
    applyStrategy: 'server',
    diffStrategy: 'server',
    injectLabels: true,
  },
  data:
    // Production environment configuration
    local config = (import '../../lib/platform/config.libsonnet').prod;
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

    namespace.withConfig(config) +
    kustomize.build(path='sealed-secrets') +
    backend.withConfig(config) +
    frontend.withConfig(config) +
    traefik.withConfig(config),
}