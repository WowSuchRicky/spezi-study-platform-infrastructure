function(config) {
  'argocd-install':: {
    apiVersion: 'v1',
    kind: 'List',
    items: [
      if obj.kind == 'Deployment' && obj.metadata.name == 'argocd-server' then
        obj {
          spec+: {
            template+: {
              spec+: {
                containers: [
                  if c.name == 'argocd-server' then
                    c {
                      command: [
                        'argocd-server',
                        '--insecure',
                        '--basehref',
                        '/argo',
                        '--rootpath',
                        '/argo',
                      ],
                    }
                  else
                    c
                  for c in super.containers
                ],
              },
            },
          },
        }
      else
        obj
      for obj in std.parseYaml(importstr 'https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml')
    ],
  },
}