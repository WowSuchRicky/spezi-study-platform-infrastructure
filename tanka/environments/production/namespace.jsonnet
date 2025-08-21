local config = import './config.jsonnet';
local namespace = import '../../lib/platform/namespace.libsonnet';

namespace.new(config)