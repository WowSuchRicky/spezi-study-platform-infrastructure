local config = import './config.jsonnet';
local oauth2Proxy = import '../../lib/platform/oauth2-proxy.libsonnet';

std.objectValues(oauth2Proxy(config).new(config))