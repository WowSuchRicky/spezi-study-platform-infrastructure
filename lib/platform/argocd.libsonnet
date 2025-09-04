{
  local k = import 'k.libsonnet',
  withConfig(config)::
    {
      // ArgoCD Ingress Route with OAuth2-proxy integration
      argocd_oauth_middleware: {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'oauth2-proxy-argo',
          namespace: config.namespace,
        },
        spec: {
          forwardAuth: {
            address: 'http://oauth2-proxy.' + config.namespace + '.svc.cluster.local/oauth2/auth?allowed_groups=ArgoCDAdmins',
            trustForwardHeader: true,
            authResponseHeaders: [],
            authRequestHeaders: [],
          },
        },
      },

      // oauth2-errors middleware already exists from traefik component

      argocd_ingress_route: {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: 'argocd-ingress',
          namespace: 'argocd',
          annotations: {
            'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
          },
        },
        spec: {
          entryPoints: ['websecure'],
          routes: [
            {
              kind: 'Rule',
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/argo`)',
              middlewares: [
                { name: 'oauth2-proxy-argo', namespace: config.namespace },
                { name: 'oauth2-errors', namespace: config.namespace },
              ],
              priority: 10,
              services: [
                {
                  name: 'argocd-server',
                  port: 80,
                },
              ],
            },
            {
              kind: 'Rule', 
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/argo`) && Header(`Content-Type`, `application/grpc`)',
              middlewares: [
                { name: 'oauth2-proxy-argo', namespace: config.namespace },
                { name: 'oauth2-errors', namespace: config.namespace },
              ],
              priority: 10,
              services: [
                {
                  name: 'argocd-server',
                  port: 80,
                  scheme: 'h2c',
                },
              ],
            },
          ],
          tls: {
            secretName: 'spezistudyplatform-main-tls-secret',
          },
        },
      },

      // ArgoCD OIDC configuration
      argocd_oidc_config: k.core.v1.configMap.new('argocd-cmd-params-cm', {
        'server.insecure': 'true',
        'server.basehref': '/argo',
        'server.rootpath': '/argo',
      })
      + k.core.v1.configMap.metadata.withNamespace('argocd'),

      argocd_server_config: k.core.v1.configMap.new('argocd-server-config', {
        'url': 'https://' + config.domain + '/argo',
        'oidc.config': std.manifestYamlDoc({
          name: 'Keycloak',
          issuer: 'https://' + config.domain + '/auth/realms/spezistudyplatform',
          clientId: 'argocd',
          clientSecret: '$ARGOCD_OIDC_CLIENT_SECRET',
          requestedScopes: ['openid', 'profile', 'email', 'argocd_groups'],
          requestedIDTokenClaims: {
            groups: {
              essential: true,
            },
          },
        }),
        'policy.default': 'role:readonly',
        'policy.csv': std.join('\n', [
          'p, role:admin, applications, *, */*, allow',
          'p, role:admin, certificates, *, *, allow', 
          'p, role:admin, clusters, *, *, allow',
          'p, role:admin, repositories, *, *, allow',
          'g, ArgoCDAdmins, role:admin',
        ]),
      })
      + k.core.v1.configMap.metadata.withNamespace('argocd'),

      

      // Note: ArgoCD OIDC client secret will be managed separately through Keycloak client secret
    }
}