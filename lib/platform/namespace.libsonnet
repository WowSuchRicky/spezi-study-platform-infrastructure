{
  withConfig(config):: {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: config.namespace,
    },
  },
}