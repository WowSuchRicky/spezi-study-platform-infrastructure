local config = import './config.jsonnet';
local keycloak = import '../../lib/platform/keycloak.libsonnet';

std.objectValues(keycloak(config).new(config))