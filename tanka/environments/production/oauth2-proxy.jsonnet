local config = import './config.jsonnet';
local oauth2Proxy = import '../../lib/platform/oauth2-proxy.libsonnet';

oauth2Proxy(config).new(config)