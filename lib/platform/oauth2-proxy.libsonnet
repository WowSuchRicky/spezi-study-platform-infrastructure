{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    local secretObject = {
      apiVersion: 'external-secrets.io/v1beta1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'oauth2-proxy-secret',
        namespace: config.namespace,
      },
      spec: {
        refreshInterval: '15s',
        secretStoreRef: {
          name: 'vault-backend',
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
            },
          },
          {
            secretKey: 'client-secret',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'client-secret',
            },
          },
          {
            secretKey: 'cookie-secret',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'cookie-secret',
            },
          },
        ],
      },
    };
    {
      oauth2_proxy_secret: secretObject,
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
            content: |||
              provider = "keycloak-oidc"
              oidc_issuer_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform"
              email_domains = ["*"]
              upstreams = ["static://200"]
              scope = "openid profile email groups"
              redirect_url = "https://%(domain)s/oauth2/callback"
              cookie_domains = ["%(domain)s"]
            ||| % { domain: config.domain, namespace: config.namespace },
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
              ['--provider-ca-file=/etc/ssl/certs/ca.crt']
          ),
          extraVolumes: if config.mode == 'PRODUCTION' then [
            {
              name: 'ca-secret',
              secret: {
                secretName: 'oauth2-proxy-ca-secret',
              },
            },
          ] else [],
          extraVolumeMounts: if config.mode == 'PRODUCTION' then [
            {
              name: 'ca-secret',
              mountPath: '/etc/ssl/certs/ca.crt',
              subPath: 'ca.crt',
              readOnly: true,
            },
          ] else [],
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