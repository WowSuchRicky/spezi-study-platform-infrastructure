// Local development environment configuration
local config = (import '../../lib/platform/config.libsonnet').localDev;
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
backend.withConfig(config) +
frontend.withConfig(config) +
keycloak.withConfig(config) +
oauth2Proxy.withConfig(config) +
traefik.withConfig(config)