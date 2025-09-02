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
          namespace: config.namespace,
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
                { name: 'oauth2-proxy' },
                { name: 'oauth2-errors' },
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
                { name: 'oauth2-proxy' },
                { name: 'oauth2-errors' },
              ],
              priority: 11,
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
            secretName: config.domain + '-main-tls-secret',
          },
        },
      },

      // ArgoCD OIDC configuration
      argocd_oidc_config: k.core.v1.configMap.new('argocd-cmd-params-cm', {
        'server.insecure': 'true',
      })
      + k.core.v1.configMap.metadata.withNamespace('argocd'),

      argocd_server_config: k.core.v1.configMap.new('argocd-server-config', {
        'url': 'https://' + config.domain + '/argo',
        'oidc.config': std.manifestYamlDoc({
          name: 'Keycloak',
          issuer: 'https://' + config.domain + '/auth/realms/spezistudyplatform',
          clientId: 'argocd',
          clientSecret: '$oidc.keycloak.clientSecret',
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

      // Secret for ArgoCD OIDC client secret - get from Keycloak client secret in external secret manager
      argocd_oidc_secret: {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'argocd-oidc-secret',
          namespace: 'argocd',
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          refreshInterval: '15s',
          secretStoreRef: {
            name: if config.externalSecrets.provider == 'gcpsm' then 'gcpsm-secret-store' else 'vault-backend',
            kind: 'ClusterSecretStore',
          },
          target: {
            name: 'argocd-oidc-secret',
            creationPolicy: 'Owner',
            template: {
              engineVersion: 'v2',
              data: {
                'oidc.keycloak.clientSecret': '{{ .clientSecret }}',
              },
            },
          },
          data: [
            {
              secretKey: 'clientSecret',
              remoteRef: {
                key: 'keycloak-argocd-client',
                property: 'client-secret',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
          ],
        },
      },

      // Note: ArgoCD OIDC client secret will be managed separately through Keycloak client secret
    }
}