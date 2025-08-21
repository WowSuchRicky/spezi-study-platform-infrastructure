local config = import './config.jsonnet';
local frontend = import '../../lib/platform/frontend.libsonnet';

std.objectValues(frontend(config))