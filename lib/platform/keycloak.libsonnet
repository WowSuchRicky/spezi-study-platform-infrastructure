{
  local helm = (import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/helm.libsonnet').new(std.thisFile),
  withConfig(config)::
    std.objectValues({
      keycloak: helm.template('keycloak', '../../charts/keycloak', {
        namespace: config.namespace,
        version: '25.1.1',
        values: {
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
          tolerations: [
            {
              key: 'node-role.kubernetes.io/control-plane',
              operator: 'Exists',
              effect: 'NoSchedule',
            },
          ],
          auth: {
            adminPassword: 'admin123!',
          },
          postgresql: {
            auth: {
              postgresPassword: 'postgres123!',
              password: 'keycloak123!',
            },
            primary: {
              tolerations: [
                {
                  key: 'node-role.kubernetes.io/control-plane',
                  operator: 'Exists',
                  effect: 'NoSchedule',
                },
              ],
            },
          },
          initContainers: |||
            - name: realm-ext-provider
              image: curlimages/curl
              imagePullPolicy: IfNotPresent
              command:
                - sh
              args:
                - -c
                - |
                  curl -L -o /emptydir/app-providers-dir/keycloakify-spezistudyplatform3-theme.jar https://s3.us-west-2.amazonaws.com/ngusav.es/Keycloak+theme+25%2B.jar
              volumeMounts:
                - name: empty-dir
                  mountPath: /emptydir
          |||,
        },
      }),
    }),
}