{
  // Traefik Helm values configuration
  helmValues(config):: {
    // Service configuration - varies by environment
    service: {
      enabled: true,
      type: config.infrastructure.loadBalancer.type,
      [if config.infrastructure.loadBalancer.staticIP != null then 'spec']: {
        loadBalancerIP: config.infrastructure.loadBalancer.staticIP,
      },
    },

    // Logging configuration
    logs: {
      general: {
        format: null,
        level: 'DEBUG',
      },
      access: {
        enabled: true,
        fields: {
          headers: {
            defaultmode: 'keep',
          },
        },
      },
    },

    // Persistence for Let's Encrypt certificates
    persistence: {
      enabled: true,
      name: if config.environment.isLocal then 'traefik' else 'traefik-data',
      accessMode: 'ReadWriteOnce',
      size: '1Gi',
      storageClass: config.infrastructure.cluster.storageClass,
      path: '/data',
      annotations: {},
    },

    // Deployment configuration
    deployment: {
      [if config.environment.isLocal then 'kind']: 'DaemonSet',
      initContainers: [
        {
          name: 'volume-permissions',
          image: 'traefik:v2.10.4',
          command: [
            'sh',
            '-c',
            'touch /data/acme.json; chown 65532:65532 /data/acme.json; chmod -v 600 /data/acme.json',
          ],
          securityContext: {
            runAsNonRoot: false,
            runAsGroup: 0,
            runAsUser: 0,
          },
          volumeMounts: [
            {
              name: if config.environment.isLocal then 'traefik' else 'traefik-data',
              mountPath: '/data',
              readOnly: false,
            },
          ],
        },
      ],
      podAnnotations: {
        "argocd.argoproj.io/sync-wave": "7",
      },
    },

    // Host ports for local development (KIND)
    [if config.infrastructure.loadBalancer.hostPorts then 'ports']: {
      web: {
        hostPort: 80,
      },
      websecure: {
        hostPort: 443,
      },
    },

    // Pod security context
    podSecurityContext: {
      fsGroupChangePolicy: 'OnRootMismatch',
      runAsGroup: 65532,
      runAsNonRoot: true,
      runAsUser: 65532,
    },

    // Enable dashboard
    ingressRoute: {
      dashboard: {
        enabled: true,
      },
    },
  },

  // Main service ingress route
  mainServiceIngressRoute(config):: {
    apiVersion: 'traefik.containo.us/v1alpha1',
    kind: 'IngressRoute',
    metadata: {
      name: config.project.name + '-main-ingress',
      namespace: config.project.namespace,
      annotations: {
        "argocd.argoproj.io/sync-wave": "7",
      },
    },
    spec: {
      entryPoints: ['websecure'],
      routes: [
        {
          match: 'Host(`' + config.domains.primary + '`)',
          kind: 'Rule',
          services: [
            {
              name: config.project.name + '-frontend',
              port: 80,
            },
          ],
          [if config.features.oauth2Proxy then 'middlewares']: [
            {
              name: 'oauth2-proxy',
            },
            {
              name: 'oauth2-errors',
            },
          ],
        },
      ],
      tls: {
        secretName: config.project.name + '-main-tls-secret',
      },
    },
  },

  // Dashboard ingress route  
  dashboardIngressRoute(config):: {
    apiVersion: 'traefik.containo.us/v1alpha1',
    kind: 'IngressRoute',
    metadata: {
      name: 'traefik-dashboard',
      namespace: 'default',
      annotations: {
        "argocd.argoproj.io/sync-wave": "7",
      },
    },
    spec: {
      entryPoints: ['web'],
      routes: [
        {
          match: 'Host(`' + config.domains.primary + '`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))',
          kind: 'Rule',
          services: [
            {
              name: 'api@internal',
              kind: 'TraefikService',
            },
          ],
        },
      ],
    },
  },

  new(config):: 
    // Use Tanka's Helm support to render the chart
    local helm = (import 'github.com/grafana/jsonnet-libs/tanka-util/helm.libsonnet').new(std.thisFile);
    
    helm.template('traefik', 'traefik/traefik', {
      values: $.helmValues(config),
      namespace: 'default',
    }) + {
      // Add our custom ingress routes
      mainServiceIngressRoute: $.mainServiceIngressRoute(config),
      dashboardIngressRoute: $.dashboardIngressRoute(config),
    },
}