local config = import './config.jsonnet';

// Import all components
local namespace = import './namespace.jsonnet';
local certManager = import './cert-manager.jsonnet';
local cloudnativePg = import './cloudnative-pg.jsonnet';
local keycloak = import './keycloak.jsonnet';
local oauth2Proxy = import './oauth2-proxy.jsonnet';
local backend = import './backend.jsonnet';
local frontend = import './frontend.jsonnet';
local traefik = import './traefik.jsonnet';

// Combine all components into a single output
namespace +
certManager +
cloudnativePg +
keycloak +
oauth2Proxy +
backend +
frontend +
traefik






