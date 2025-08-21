local config = import './config.jsonnet';
local certManager = import '../../lib/platform/cert-manager.libsonnet';

certManager(config)['cert-manager']