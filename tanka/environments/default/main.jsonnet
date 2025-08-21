local config = import '../../lib/platform/config.libsonnet';
local namespace = import '../../lib/platform/namespace.libsonnet';
local certManager = import '../../lib/platform/cert-manager.libsonnet';
local cloudnativePg = import '../../lib/platform/cloudnative-pg.libsonnet';
local keycloak = import '../../lib/platform/keycloak.libsonnet';
local oauth2Proxy = import '../../lib/platform/oauth2-proxy.libsonnet';
local backend = import '../../lib/platform/backend.libsonnet';
local frontend = import '../../lib/platform/frontend.libsonnet';
local traefik = import '../../lib/platform/traefik.libsonnet';

// Default deployment (development environment)
local defaultConfig = config.default {
  project: {
    name: 'spezistudyplatform',
    namespace: 'spezistudyplatform',
    displayName: 'Spezi Study Platform',
  },
  
  domains: {
    primary: 'localhost',
    auth: 'localhost/auth',
  },
  
  environment: {
    name: 'default',
    mode: 'DEV',
    isDev: true,
    isLocal: false,
  },
  
  infrastructure: {
    tls: {
      issuer: 'selfsigned-issuer',
      staging: false,
      selfSigned: true,
    },
    
    loadBalancer: {
      enabled: false,
      staticIP: null,
      type: 'ClusterIP',
      hostPorts: false,
    },
  },
  
  auth: {
    oauth2Proxy: {
      insecureSkipVerify: true,
      cookieSecure: false,
      codeChallenge: true,
    },
  },
  
  features: {
    argocd: false,
    oauth2Proxy: true,
    sealedSecrets: false,
  },
};

namespace.new(defaultConfig) +
certManager(defaultConfig) +
cloudnativePg(defaultConfig) +
keycloak(defaultConfig).new(defaultConfig) +
oauth2Proxy.new(defaultConfig) +
backend(defaultConfig) +
frontend(defaultConfig) +
traefik.new(defaultConfig)
