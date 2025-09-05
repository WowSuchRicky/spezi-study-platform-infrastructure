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
            authResponseHeaders: [
              'X-Forwarded-User',
              'X-Forwarded-Email',
              'X-Forwarded-Groups',
              'X-Forwarded-Preferred-Username',
            ],
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
          name: 'OAuth2-Proxy',
          issuer: 'https://' + config.domain + '/argo/api/dex',
          clientId: 'argo-workflows-sso',
          clientSecret: 'unused',
          requestedScopes: ['openid', 'profile', 'email', 'groups'],
        }),
        'dex.config': std.manifestYamlDoc({
          issuer: 'https://' + config.domain + '/argo/api/dex',
          storage: {
            type: 'memory',
          },
          web: {
            http: '0.0.0.0:5556',
          },
          logger: {
            level: 'debug',
            format: 'text',
          },
          oauth2: {
            skipApprovalScreen: true,
          },
          staticClients: [
            {
              id: 'argo-workflows-sso',
              redirectURIs: ['https://' + config.domain + '/argo/auth/callback'],
              name: 'ArgoCD',
              secret: 'unused',
            },
          ],
          connectors: [
            {
              type: 'authproxy',
              id: 'oauth2-proxy',
              name: 'OAuth2-Proxy',
              config: {
                userHeader: 'X-Forwarded-User',
                emailHeader: 'X-Forwarded-Email',
                groupsHeader: 'X-Forwarded-Groups',
              },
            },
          ],
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