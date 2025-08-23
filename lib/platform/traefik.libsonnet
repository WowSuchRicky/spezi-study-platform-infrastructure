local helm = (import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/helm.libsonnet').new(std.thisFile),

{
  withConfig(config)::
    std.objectValues({
      traefik: helm.template('traefik', '../../charts/traefik', {
        namespace: config.namespace,
        values: {
          service: {
            enabled: true,
            type: 'LoadBalancer',
            [if config.loadBalancerIP != null then 'spec']: {
              loadBalancerIP: config.loadBalancerIP,
            },
          },
          logs: {
            general: {
              level: 'DEBUG',
            },
            access: {
              enabled: true,
              fields: {
                headers: {
                  defaultmode: 'keep',
                },
              },
            },
          },
          persistence: {
            enabled: true,
            name: 'traefik-data',
            accessMode: 'ReadWriteOnce',
            size: '1Gi',
            storageClass: config.storageClass,
            path: '/data',
            annotations: {},
          },
          deployment: {
            initContainers: [
              {
                name: 'volume-permissions',
                image: 'traefik:v2.10.4',
                command: [
                  'sh',
                  '-c',
                  'touch /data/acme.json; chown 65532:65532 /data/acme.json; chmod -v 600 /data/acme.json',
                ],
                securityContext: {
                  runAsNonRoot: false,
                  runAsGroup: 0,
                  runAsUser: 0,
                },
                volumeMounts: [
                  {
                    name: 'traefik-data',
                    mountPath: '/data',
                    readOnly: false,
                  },
                ],
              },
            ],
          },
          podSecurityContext: {
            fsGroupChangePolicy: 'OnRootMismatch',
            runAsGroup: 65532,
            runAsNonRoot: true,
            runAsUser: 65532,
          },
          ingressRoute: {
            dashboard: {
              enabled: true,
            },
          },
        },
      }),
  }),
}