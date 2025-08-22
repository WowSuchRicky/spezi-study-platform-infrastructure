local k = import 'k.libsonnet';

{
  withConfig(config):: {
    // Frontend ConfigMap
  frontendConfig: k.core.v1.configMap.new('spezistudyplatform-frontend-config', {
    'VITE_API_BASE': 'https://' + config.domain + '/',
    'OAUTH_AUTHORITY': 'https://' + config.domain + '/auth/realms/spezistudyplatform',
    'OAUTH_REDIRECT_URI': 'https://' + config.domain,
    'OAUTH_CLIENT_ID': 'spezistudyplatform',
  }) + k.core.v1.configMap.mixin.metadata.withNamespace(config.namespace),

  // Frontend Deployment
  frontendDeployment: k.apps.v1.deployment.new(
    'spezistudyplatform-frontend',
    1,
    [
      k.core.v1.container.new('spezistudyplatform-frontend-container', 'traefik/whoami:latest')
      + k.core.v1.container.withImagePullPolicy('Always')
      + k.core.v1.container.withPorts([k.core.v1.containerPort.new(80)])
      + k.core.v1.container.resources.withLimits({ memory: '1Gi', cpu: '100m' })
      + k.core.v1.container.withEnvFrom([
          k.core.v1.envFromSource.configMapRef.withName('spezistudyplatform-frontend-config'),
        ]),
    ]
  )
  + k.apps.v1.deployment.mixin.metadata.withNamespace(config.namespace)
  + k.apps.v1.deployment.mixin.metadata.withLabels({ app: 'spezistudyplatform-frontend' })
  + k.apps.v1.deployment.mixin.spec.selector.withMatchLabels({ app: 'spezistudyplatform-frontend' })
  + k.apps.v1.deployment.mixin.spec.template.metadata.withLabels({ app: 'spezistudyplatform-frontend' })
  + k.apps.v1.deployment.mixin.spec.template.spec.withTolerations([
      {
        key: 'node-role.kubernetes.io/control-plane',
        operator: 'Exists',
        effect: 'NoSchedule',
      },
    ])
    + k.apps.v1.deployment.mixin.spec.strategy.withType('Recreate'),

    // Frontend Service
    frontendService: k.core.v1.service.new(
      'spezistudyplatform-frontend-service',
      { app: 'spezistudyplatform-frontend' },
      [k.core.v1.servicePort.new(80, 80) + k.core.v1.servicePort.withName('main')]
    )
    + k.core.v1.service.mixin.metadata.withNamespace(config.namespace)
    + k.core.v1.service.mixin.spec.withType('ClusterIP'),
  },
}