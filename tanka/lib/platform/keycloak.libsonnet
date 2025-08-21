
function(config) 
{
    helmValues(config):: {
      commonAnnotations: {
        "argocd.argoproj.io/sync-wave": "3",
      },
      extraEnvVars: [
        {
          name: 'KC_PROXY_HEADERS',
          value: 'xforwarded',
        },
        {
          name: 'KC_HTTP_RELATIVE_PATH',
          value: '/auth',
        },
      ],
      customReadinessProbe: {
        failureThreshold: 3,
        httpGet: {
          path: '/auth/realms/master',
          port: 8080,
        },
        initialDelaySeconds: 120,
      },
      resources: {
        limits: {
          cpu: '1000m',
          memory: '2048Mi',
        },
        requests: {
          cpu: '500m',
          memory: '1024Mi',
        },
      },
      initContainers: [
        {
          name: 'realm-ext-provider',
          image: 'curlimages/curl',
          imagePullPolicy: 'IfNotPresent',
          command: [
            'sh',
            '-c',
            'curl -L -o /emptydir/app-providers-dir/keycloakify-spezistudyplatform3-theme.jar https://s3.us-west-2.amazonaws.com/ngusav.es/Keycloak+theme+25%2B.jar',
          ],
          volumeMounts: [
            {
              name: 'empty-dir',
              mountPath: '/emptydir',
            },
          ],
        },
      ],
    },

    new(config)::
      local helm = (import 'github.com/grafana/jsonnet-libs/tanka-util/helm.libsonnet').new(std.thisFile);

      helm.template('keycloak', '../../charts/keycloak', {
        values: $.helmValues(config),
        namespace: config.project.namespace,
      }),
}
