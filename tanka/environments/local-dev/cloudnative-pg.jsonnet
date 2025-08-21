local config = import './config.jsonnet';
local cloudnativePg = import '../../lib/platform/cloudnative-pg.libsonnet';

cloudnativePg(config)