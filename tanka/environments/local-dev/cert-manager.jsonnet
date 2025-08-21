// Simple cert-manager namespace for now (ArgoCD can't import remote URLs)
[
  {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: 'cert-manager',
      annotations: {
        'argocd.argoproj.io/sync-wave': '1',
      },
    },
  },
]