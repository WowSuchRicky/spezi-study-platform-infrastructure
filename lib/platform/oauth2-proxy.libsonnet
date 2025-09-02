{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    local secretObject = {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'oauth2-proxy-secret',
        namespace: config.namespace,
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
          name: 'oauth2-proxy-secret',
          creationPolicy: 'Owner',
        },
        data: [
          {
            secretKey: 'client-id',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'client-id',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          },
          {
            secretKey: 'client-secret',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'client-secret',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          },
          {
            secretKey: 'cookie-secret',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'cookie-secret',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          },
        ],
      },
    };
    {
      oauth2_proxy_secret: secretObject,
      // PushSecret for oauth2-proxy client-secret (only for GCP Secret Manager)
      oauth2_proxy_client_secret_push: if config.externalSecrets.provider == 'gcpsm' then {
        apiVersion: 'external-secrets.io/v1alpha1',
        kind: 'PushSecret',
        metadata: {
          name: 'oauth2-proxy-client-secret-push',
          namespace: 'external-secrets-system',
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          updatePolicy: 'Replace',
          refreshInterval: '24h',
          secretStoreRefs: [
            {
              name: 'gcpsm-secret-store',
              kind: 'ClusterSecretStore',
            },
          ],
          selector: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'Password',
              name: 'oauth-secret-generator',
            },
          },
          data: [
            {
              match: {
                secretKey: 'password',
                remoteRef: {
                  remoteKey: 'oauth2-proxy-secret',
                  property: 'client-secret',
                },
              },
            },
          ],
        },
      } else {},
      // PushSecret for oauth2-proxy cookie-secret (only for GCP Secret Manager)
      oauth2_proxy_cookie_secret_push: if config.externalSecrets.provider == 'gcpsm' then {
        apiVersion: 'external-secrets.io/v1alpha1',
        kind: 'PushSecret',
        metadata: {
          name: 'oauth2-proxy-cookie-secret-push',
          namespace: 'external-secrets-system',
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          updatePolicy: 'Replace',
          refreshInterval: '24h',
          secretStoreRefs: [
            {
              name: 'gcpsm-secret-store',
              kind: 'ClusterSecretStore',
            },
          ],
          selector: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'Password',
              name: 'cookie-secret-generator',
            },
          },
          data: [
            {
              match: {
                secretKey: 'password',
                remoteRef: {
                  remoteKey: 'oauth2-proxy-secret',
                  property: 'cookie-secret',
                },
              },
            },
          ],
        },
      } else {},
      // PushSecret for oauth2-proxy client-id (static value, only for GCP Secret Manager)
      oauth2_proxy_client_id_push: if config.externalSecrets.provider == 'gcpsm' then {
        apiVersion: 'external-secrets.io/v1alpha1',
        kind: 'PushSecret',
        metadata: {
          name: 'oauth2-proxy-client-id-push',
          namespace: 'external-secrets-system',
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          updatePolicy: 'Replace',
          refreshInterval: '24h',
          secretStoreRefs: [
            {
              name: 'gcpsm-secret-store',
              kind: 'ClusterSecretStore',
            },
          ],
          selector: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'Fake',
              name: 'oauth2-proxy-client-id-generator',
            },
          },
          data: [
            {
              match: {
                secretKey: 'client-id',
                remoteRef: {
                  remoteKey: 'oauth2-proxy-secret',
                  property: 'client-id',
                },
              },
            },
          ],
        },
      } else {},
    } + (
      if config.mode == 'PRODUCTION' then {
        'oauth2-proxy-ca-secret': {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: 'oauth2-proxy-ca-secret',
            namespace: config.namespace,
          },
          type: 'Opaque',
          stringData: {
            'ca.crt': config.caCrt,
          },
        },
      } else {}
    ) + {
      oauth2_proxy: helm.template('oauth2-proxy', '../../charts/oauth2-proxy', {
        namespace: config.namespace,
        values: {
          configuration: {
            content: (
              if config.mode == 'DEV' then |||
                provider = "keycloak-oidc"
                oidc_issuer_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform"
                email_domains = ["*"]
                upstreams = ["static://200"]
                scope = "openid profile email groups"
                redirect_url = "https://%(domain)s/oauth2/callback"
                cookie_domains = ["%(domain)s"]
              ||| % { domain: config.domain, namespace: config.namespace } else |||
                provider = "keycloak-oidc"
                oidc_issuer_url = "https://%(domain)s/auth/realms/spezistudyplatform"
                email_domains = ["*"]
                upstreams = ["static://200"]
                scope = "openid profile email groups"
                redirect_url = "https://%(domain)s/oauth2/callback"
                cookie_domains = ["%(domain)s"]
              ||| % { domain: config.domain, namespace: config.namespace }
            ),
            existingSecret: 'oauth2-proxy-secret',
          },
          ingress: {
            enabled: false,
          },
          extraArgs: [
            '--skip-provider-button=true',
            '--whitelist-domain=*.' + config.domain,
            '--allowed-role=spezistudyplatform-authorized-users',
            '--pass-access-token=true',
            '--cookie-csrf-expire=60m',
            '--pass-authorization-header=true',
            '--set-xauthrequest=true',
            '--code-challenge-method=S256',
          ] + (
            if config.mode == 'DEV' then
              ['--insecure-oidc-skip-issuer-verification=true']
            else
              []
          ),
          extraVolumes: [],
          extraVolumeMounts: [],
          redis: {
            enabled: false,
          },
          sessionStorage: {
            type: 'cookie',
          },
          extraEnv: [
            {
              name: 'OAUTH2_PROXY_REVERSE_PROXY',
              value: 'true',
            },
          ],
        },
      }),
    }
}