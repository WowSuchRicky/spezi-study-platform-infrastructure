local k = import 'k.libsonnet',

{
  withConfig(config)::
    std.objectValues({
      postgres_credentials: k.core.v1.secret.new('spezistudyplatform-postgres-credentials', {
        username: std.base64('spezistudyplatform'),
        password: std.base64('spezistudyplatform1!2@'),
      })
      + k.core.v1.secret.metadata.withNamespace(config.namespace)
      + k.core.v1.secret.withType('kubernetes.io/basic-auth'),

      backend_secret: k.core.v1.secret.new('spezistudyplatform-backend-secret', {
        OAUTH_CLIENT_SECRET: 'Tmd2RUFQcFJaTzA5MENWcDEybHdNUDFyVzVDcTdJQ2EK',
      })
      + k.core.v1.secret.metadata.withNamespace(config.namespace),

      backend_config: k.core.v1.configMap.new('spezistudyplatform-backend-config', {
        PORT: '3003',
        MODE: config.mode, 
        ALLOWED_ORIGINS: "('https://" + config.domain + "', 'http://" + config.domain + "'),http://127.0.0.1,http://localhost:5173",
        AUTH_URL: 'https://' + config.domain + '/auth',
        OAUTH_REALM: 'spezistudyplatform',
        OAUTH_CLIENT_ID: 'spezistudyplatform',
        DB_HOST: 'spezistudyplatform-db-rw',
        DB_NAME: 'spezistudyplatform',
      })
      + k.core.v1.configMap.metadata.withNamespace(config.namespace),

      backend_deployment: k.apps.v1.deployment.new(
        name='spezistudyplatform-backend',
        replicas=1,
        containers=[
          k.core.v1.container.new('spezistudyplatform-backend-container', 'traefik/whoami:latest')
          + k.core.v1.container.withImagePullPolicy('Always')
          + k.core.v1.container.withPorts([k.core.v1.containerPort.new(3000)])
          + k.core.v1.container.resources.withLimits({
            memory: '2Gi',
            cpu: '1',
          })
          + k.core.v1.container.withEnvFrom([
            k.core.v1.envFromSource.configMapRef.withName('spezistudyplatform-backend-config')
          ])
          + k.core.v1.container.withEnv([
            k.core.v1.envVar.fromSecretRef('DB_USER', 'spezistudyplatform-postgres-credentials', 'username'),
            k.core.v1.envVar.fromSecretRef('DB_PASSWORD', 'spezistudyplatform-postgres-credentials', 'password'),
          ])
        ]
      )
      + k.apps.v1.deployment.metadata.withNamespace(config.namespace)
      + k.apps.v1.deployment.metadata.withLabels({ app: 'spezistudyplatform-backend' })
      + k.apps.v1.deployment.spec.selector.withMatchLabels({ app: 'spezistudyplatform-backend' })
      + k.apps.v1.deployment.spec.template.metadata.withLabels({ app: 'spezistudyplatform-backend' })
      + k.apps.v1.deployment.spec.strategy.withType('Recreate'),

      backend_service: k.core.v1.service.new(
        'spezistudyplatform-backend-service',
        { app: 'spezistudyplatform-backend' },
        [k.core.v1.servicePort.new(3000, 3000)]
      )
      + k.core.v1.service.metadata.withNamespace(config.namespace),
  }),
}