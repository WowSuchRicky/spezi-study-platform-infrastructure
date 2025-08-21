local config = import './config.jsonnet';
local keycloak = import '../../lib/platform/keycloak.libsonnet';

keycloak(config).new(config)