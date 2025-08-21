local config = import './config.jsonnet';
local traefik = import '../../lib/platform/traefik.libsonnet';

traefik.new(config)