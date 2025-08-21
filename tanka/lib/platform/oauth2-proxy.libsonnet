
function(config) 
{
    helmValues(config):: {
      podAnnotations: {
        "argocd.argoproj.io/sync-wave": "4",
      },
      deploymentAnnotations: {
        "argocd.argoproj.io/sync-wave": "4",
      },
      config: {
        configFile: |||
          provider = "keycloak-oidc"
          oidc_issuer_url = "%s/auth/realms/spezistudyplatform"
          email_domains = ["*"]
          upstreams = ["static://200"]
          scope = "openid profile email groups"
          redirect_url = "%s/oauth2/callback"
          cookie_domains = ["%s"]
        ||| % [config.domains.primary, config.domains.primary, config.domains.primary],
      },
      ingress: {
        enabled: false,
      },
      extraArgs:
        [
          '--skip-provider-button=true',
          '--allowed-role=spezistudyplatform-authorized-users',
          '--pass-access-token=true',
          '--cookie-csrf-expire=60m',
          '--pass-authorization-header=true',
          '--set-xauthrequest=true',
          '--code-challenge-method=S256',
        ] +
        (if config.auth.oauth2Proxy.insecureSkipVerify then
          [
            '--insecure-oidc-skip-issuer-verification=true',
            '--ssl-insecure-skip-verify=true',
          ]
        else []) +
        (if !config.auth.oauth2Proxy.cookieSecure then
          [
            '--cookie-secure=false',
          ]
        else []) +
        [
          '--whitelist-domain=*.%s' % config.domains.primary,
        ],
      redis: {
        enabled: true,
        architecture: 'standalone',
      },
      sessionStorage: {
        type: 'redis',
      },
      proxyVarsAsSecrets: false, // Set to false to use extraEnv
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

    new(config)::
      local helm = (import 'github.com/grafana/jsonnet-libs/tanka-util/helm.libsonnet').new(std.thisFile);

      helm.template('oauth2-proxy', '../../charts/oauth2-proxy', {
        values: $.helmValues(config),
        namespace: config.project.namespace,
        version: '8.1.0', // Use the specified chart version
      }),
}
