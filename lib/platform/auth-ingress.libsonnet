{
  withConfig(config)::
    {
      'keycloak-ingress': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: 'keycloak-ingress',
          namespace: config.namespace,
          annotations: {
            'ingress.kubernetes.io/ssl-redirect': 'true',
            'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
            'ingress.kubernetes.io/proxy-buffer-size': '128k',
          },
        },
        spec: {
          entryPoints: [
            'websecure',
          ],
          routes: [
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/oauth2`)',
              priority: 99,
              kind: 'Rule',
              services: [
                {
                  name: 'oauth2-proxy',
                  port: 80,
                },
              ],
              middlewares: [],
            },
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/auth`)',
              priority: 99,
              kind: 'Rule',
              services: [
                {
                  name: 'keycloak',
                  port: 80,
                },
              ],
              middlewares: [],
            },
          ],
          tls: {
            secretName: config.namespace + '-main-tls-secret',
          },
        },
      },
    },
}