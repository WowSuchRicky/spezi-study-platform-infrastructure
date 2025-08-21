local config = import './config.jsonnet';
local frontend = import '../../lib/platform/frontend.libsonnet';

{
  apiVersion: 'v1',
  kind: 'List',
  items: std.objectValues(frontend(config))
}