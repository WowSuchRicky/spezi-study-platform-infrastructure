local config = import './config.jsonnet';
local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';

// Production deployment
argocdApps(config)






