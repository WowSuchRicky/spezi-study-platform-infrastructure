local config = import './config.jsonnet';
local backend = import '../../lib/platform/backend.libsonnet';

backend(config)