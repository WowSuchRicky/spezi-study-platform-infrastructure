{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    std.objectValues({
      traefik: helm.template('traefik', '../../charts/traefik', {
        namespace: config.namespace,
        values: {
          service: {
            enabled: true,
            type: if config.mode == 'DEV' then 'ClusterIP' else 'LoadBalancer',
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
      
      // OAuth2 Proxy Middleware for forward authentication
      'oauth2-proxy-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'oauth2-proxy',
          namespace: config.namespace,
        },
        spec: {
          forwardAuth: {
            address: 'http://oauth2-proxy.' + config.namespace + '.svc.cluster.local/oauth2/auth_or_start',
            trustForwardHeader: true,
            authResponseHeaders: [
              'X-Auth-Request-User',
              'X-Auth-Request-Email',
              'X-Auth-Request-Groups',
              'X-Auth-Request-Access-Token',
            ],
            authRequestHeaders: [],
          },
        },
      },

      // OAuth2 Error Handling Middleware
      'oauth2-errors-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'oauth2-errors',
          namespace: config.namespace,
        },
        spec: {
          errors: {
            status: [
              '401-403',
            ],
            service: {
              name: 'oauth2-proxy',
              port: 80,
            },
            query: '/oauth2/sign_in?rd={url}',
          },
        },
      },

      // Main application IngressRoute with OAuth2 protection
      'main-application-ingress': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: config.namespace + '-ingress',
          namespace: config.namespace,
          annotations: {
            'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
            'ingress.kubernetes.io/proxy-buffer-size': '128k',
            'ingress.kubernetes.io/auth-response-headers': 'X-Auth-Request-User, X-Auth-Request-Email, X-Auth-Request-Groups',
          },
        },
        spec: {
          entryPoints: [
            'websecure',
          ],
          routes: [
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/`)',
              priority: 1,
              kind: 'Rule',
              services: [
                {
                  name: config.namespace + '-frontend-service',
                  port: 80,
                },
              ],
              middlewares: [
                { name: 'oauth2-proxy' },
                { name: 'oauth2-errors' },
              ],
            },
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/backend`)',
              priority: 2,
              kind: 'Rule',
              services: [
                {
                  name: config.namespace + '-backend-service',
                  port: 3000,
                },
              ],
              middlewares: [
                { name: 'oauth2-proxy' },
                { name: 'oauth2-errors' },
              ],
            },
          ],
          tls: {
            secretName: config.namespace + '-main-tls-secret',
          },
        },
      },

      // Traefik Dashboard IngressRoute
      'traefik-dashboard-ingress': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: 'dashboard',
          namespace: config.namespace,
          annotations: {
            'traefik.ingress.kubernetes.io/router.tls': 'true',
          },
        },
        spec: {
          entryPoints: [
            'web',
          ],
          routes: [
            {
              match: "PathPrefix('/dashboard')",
              kind: 'Rule',
              services: [
                {
                  name: 'api@internal',
                },
              ],
            },
          ],
        },
      },
    }),
}