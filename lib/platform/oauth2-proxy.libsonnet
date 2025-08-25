{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    local secretObject = 
      if std.get(config, 'mode', 'DEV') == 'DEV' then
        // For local dev, use a simple Kubernetes secret
        {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: 'oauth2-proxy-secret',
            namespace: config.namespace,
          },
          type: 'Opaque',
          data: {
            'client-id': std.base64('oauth2-proxy'),
            'client-secret': std.base64('c4h7rptpKNYyHOpuH780CXEGyLvYmo6A'),
            'cookie-secret': std.base64('local-dev-cookie-secret-32-chars'),
          },
        }
      else
        // For production, use the SealedSecret
        {
          apiVersion: 'bitnami.com/v1alpha1',
          kind: 'SealedSecret',
          metadata: {
            creationTimestamp: null,
            name: 'oauth2-proxy-secret',
            namespace: config.namespace,
          },
          spec: {
            encryptedData: {
              'client-id': 'AgCIdjfJ5vQTOHhrTz3xvvjypLVjiX5yMFrKTXl+aBHAQcW2F8XZn4FZlYbYvSNmfl4Gwpu5OxiDx7fCmfT5a0yVRcTIP4yKWosv4NpjISGKy4xVCIoKftsu5p/7jKPA/Cy5Tzb5wdTHPJelBzMlbbJeqpAgdM+yLaSfIJkk3/Dnydq6snmVWm6xcUd77MTe68imWjBu5IthXJWUtx4U3LnNHpcv5+Ax97io4lO4YoqAe02z5wgFoLCRfkB1ckbEyZQxXBB8LT1BHLJk608po0u2Tx3XGZTFZ7/v42iVsTdAd1VJJH1BTFUnlUUg/vVbWAsDRqi4jCS/Jg2o/UtO2EeBf326oPXbyGkam/dupUtFGNbWQqwfMcIFZSiua/Zy3wNa9WOSVkVtUJjr5Fv8Oa2YC+6C7YkOdpU1O22z3egP6Wu3LCk7CHlTaFlGvwDgkS3vCoAqTnBR7vCsD5givW6COPCb4SoOyy9sgahCtFqkFs9u+N54M6r5DkmsQ1hpmkIrJu6tyb+FqxLO0WCYvEP2vZfeFw4lUpHNkXDfaraCl0wSOS3QHUngyZOzZTjwMNpFyzLquJgcdthChCVITzI1yLqoMYlnCUybK52lO53m49/+GlqCZIAHOqFWMkIRLIATIMjgpWSk+w3DfsnJhjq7J/sWJSmVQEnzMgvdvA3C+tOPJPXk3RmH/zp5o27IpXSCC+D+CJNZEa0vYBQ=',
              'client-secret': 'AgBS8cO3Q8QfGpIz4pYiN1QUQJXEjvZh/uvSWnksQgugR4+EP8YAxDkhMXAoPuM7NE3MXTdTocRvkIoWa/j3XzylgAyP5LB/ALYlnQqULy5/mia48XehyRtNjwaSIGf8EyYKhb14B5+n7Zk42pKAUvW215wbJwoUpL1e6iZhfnY5ROrx2/JgmoPQk0Ts1PaSpMjUgRrtJA0OFOS+Q6P45ntlR8W6ahlYgLsBcBafH2c34/Y0H/VIz565qLDw0GDNECug9oXx8wfQlVTpk9YUiHPBnUgB72xp/rqEp8+gRfVjHPHtUrx/hAATV+vGxZ16aO58f5gqdXceHe7w5Eh0tIWortXyHPRa+YhYz2Vg2soU4hvzsEAiD+BNY3fVSImi8bcBqOM47jPQquzMen2FS/1663TZfvjNZ3NwT2TVEQMScL+mF6DbZlKVNLOg9Lbyawo7ZOxeJ0/AOO+8dTfUZHRB7dOUculuY8cQMVMbKwaigjIaCwFJfo2H07jkYFqenkfLZ8egflhVsgsMows1u4OL2KQdzcSjO/3XDILA9npgXp+V438oOrmnS30MtONHnvvEsomlzVJxxUMLs6u/M2ZngBGzu53QJqKz4pvXo4KL2CbH5KcAdoQAznWJTBjY4yOmAxmnKjNiZROvlk59g1Lltz8ootfp7GahSsLj49iAQJdj9KOijH+C3Zno5nT/QqTOeeJ5RAc35d00/Aib6/F3Dg1ffkJD/VJz67ZasFiAhQ==',
              'cookie-secret': 'AgAJWcDyxb/7G/kY4LrtQtJTXjXHwORJ/VbZf91OfV1obqzlaY2vGF+BQ6+dRx0Gro8k8eS+Xvruj+RL8DI5xQAtl/NxjIjOSDoVmSTAgrzjH3RthIsE3b/XuchwkiXWinNrmO/k/7anijmRbbhEGID+9q+zY/7tIL5KvCxsHdmXaapNFYHnr41ELsHZZ0C2OOc6BeYFAX7Nh4qesq6FMMNbdNUZSAso1lDiq/JEeWAwkh+/88uhIQfq/8xpLGO6u7hxze6N8w8h2Ly4/Uknrvy6PLo5jZWhJgsclGq/a1qx5OQwa39R3rPsqlxSi10Q0MzqQIa/WhA/KZH5sodEoK6D1MdwKHyxEhGzEy9Z5+3lZmbfZA9sLAYez+hI62DlJDTWMRdtetENr8GijSE7JuWmNMYCszSFvGKCL1dnYfZASj1IxOk8SiNoJ1+5dPAQrK6KGeRpiHhzmJ4Y3nJsciVUNXjMi/pXgEwAXkjpb3854McItfkZyqv04FkcsPlZ/zh0tHh7kICGHBUbrjO4CIcCBYmuCEDv012mm890+G3Lq5M1mhgqTYnRZQov+1t/rj+J8nU0OCD7gZZL6Mu2Pvl4jDCVk4RXiwhpz2Vl+PF9mMuh0AhF72A9331Nf3YLTastjYEQ4auTCTH9PvMu8NibV7rKyvHV8TN5u/yE9pvr/JDFUPmxVm4PdF4vVpsba33EOhAqG13xveqdZL9XFfLJfDnD9e5Eia/NBR9iYIvMW6z/c7GeEZS9VRbG5w==',
            },
            template: {
              metadata: {
                creationTimestamp: null,
                name: 'oauth2-proxy-secret',
                namespace: config.namespace,
              },
              type: 'Opaque',
            },
          },
        };
    std.objectValues({
      oauth2_proxy_secret: secretObject,
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
          configuration: {
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
            '--insecure-oidc-skip-issuer-verification=true',
            '--provider-ca-file=/etc/ssl/certs/ca.crt',
          ],
          extraVolumes: [
            {
              name: 'ca-secret',
              secret: {
                secretName: 'oauth2-proxy-ca-secret',
              },
            },
          ],
          extraVolumeMounts: [
            {
              name: 'ca-secret',
              mountPath: '/etc/ssl/certs/ca.crt',
              subPath: 'ca.crt',
              readOnly: true,
            },
          ],
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
    }),
}