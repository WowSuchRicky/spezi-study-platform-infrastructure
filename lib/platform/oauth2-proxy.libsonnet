{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    std.objectValues({
      oauth2_proxy: helm.template('oauth2-proxy', '../../charts/oauth2-proxy', {
        namespace: config.namespace,
        values: {
          config: {
            configFile: |||
              provider = "keycloak-oidc"
              oidc_issuer_url = "https://%(domain)s/auth/realms/spezistudyplatform"
              email_domains = ["*"]
              upstreams = ["static://200"]
              scope = "openid profile email groups"
              redirect_url = "https://%(domain)s/oauth2/callback"
              cookie_domains = ["%(domain)s"]
            ||| % { domain: config.domain },
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
          ],
          redis: {
            enabled: true,
            architecture: 'standalone',
          },
          sessionStorage: {
            type: 'redis',
          },
          extraEnv: [
            {
              name: 'OAUTH2_PROXY_REVERSE_PROXY',
              value: 'true',
            },
            {
              name: 'OAUTH2_PROXY_CLIENT_ID',
              valueFrom: {
                secretKeyRef: {
                  name: 'oauth2-proxy-secret',
                  key: 'client-id',
                },
              },
            },
            {
              name: 'OAUTH2_PROXY_CLIENT_SECRET',
              valueFrom: {
                secretKeyRef: {
                  name: 'oauth2-proxy-secret',
                  key: 'client-secret',
                },
              },
            },
            {
              name: 'OAUTH2_PROXY_COOKIE_SECRET',
              valueFrom: {
                secretKeyRef: {
                  name: 'oauth2-proxy-secret',
                  key: 'cookie-secret',
                },
              },
            },
          ],
        },
      }),
    }),
}