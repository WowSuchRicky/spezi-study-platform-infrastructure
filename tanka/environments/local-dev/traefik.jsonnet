local config = import './config.jsonnet';
local traefik = import '../../lib/platform/traefik.libsonnet';

std.objectValues(traefik.new(config))