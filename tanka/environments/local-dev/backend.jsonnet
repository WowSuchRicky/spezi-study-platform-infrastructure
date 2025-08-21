local config = import './config.jsonnet';
local backend = import '../../lib/platform/backend.libsonnet';

std.objectValues(backend(config))