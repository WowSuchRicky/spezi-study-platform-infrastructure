// Simple placeholder for CloudNative-PG (ArgoCD can't import remote URLs)
[
  {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'cloudnative-pg-placeholder',
      namespace: 'spezistudyplatform',
      annotations: {
        'argocd.argoproj.io/sync-wave': '2',
      },
    },
    data: {
      message: 'CloudNative-PG deployment placeholder',
    },
  },
]