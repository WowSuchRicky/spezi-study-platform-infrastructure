local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';
// Production ArgoCD bootstrap configuration
local config = (import '../../lib/platform/config.libsonnet').prod;
argocdApps.withConfig(config)