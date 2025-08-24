local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';
// This config can be expanded later if needed. For now, a dummy namespace is sufficient
// as the libsonnet file doesn't use it for much yet.
local config = { namespace: 'argocd' };
argocdApps.withConfig(config)