local config = import './config.jsonnet';
local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';

local appOfApps = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'Application',
  metadata: {
    name: config.project.name + '-apps',
    namespace: 'argocd',
    finalizers: [
      'resources-finalizer.argocd.argoproj.io',
    ],
  },
  spec: {
    project: 'default',
    source: {
      repoURL: 'https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git',
      targetRevision: 'HEAD',
      path: 'tanka/environments/' + config.environment.name,
      directory: {
        jsonnet: {},
        include: 'argocd-apps.jsonnet',
      },
    },
    destination: {
      server: 'https://kubernetes.default.svc',
      namespace: 'argocd',
    },
    syncPolicy: {
      automated: {
        prune: true,
        selfHeal: true,
      },
      syncOptions: [
        'CreateNamespace=true',
      ],
    },
  },
};

local componentApps = argocdApps(config);

// Return apps directly without List wrapper
[appOfApps] + std.objectValues(componentApps)
