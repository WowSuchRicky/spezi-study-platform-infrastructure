local app(name, path) = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'Application',
  metadata: {
    name: name,
    namespace: 'argocd',
    finalizers: [
      'resources-finalizer.argocd.argoproj.io',
    ],
  },
  spec: {
    project: 'default',
    source: {
      repoURL: 'https://github.com/WowSuchRicky/spezi-study-platform-infrastructure.git',
      path: path,
      targetRevision: 'jsonnet-working',
      plugin: {
        name: 'tanka',
      },
    },
    destination: {
      server: 'https://kubernetes.default.svc',
      namespace: name,
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

{
  'default-app': app('default', 'environments/default'),
  'local-dev-app': app('local-dev', 'environments/local-dev'),
}
