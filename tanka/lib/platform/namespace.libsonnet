{
  new(config):: {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: config.project.namespace,
      annotations: {
        "argocd.argoproj.io/sync-wave": "0",
      },
    },
  },
}