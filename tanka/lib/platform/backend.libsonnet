
function(config) 
{
    "backend-configmap": {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: config.project.name + "-backend-config",
        namespace: config.project.namespace,
        annotations: {
          "argocd.argoproj.io/sync-wave": "5",
        },
      },
      data: {
        PORT: std.toString(config.applications.backend.port),
        MODE: config.environment.mode,
        ALLOWED_ORIGINS: std.join(",", config.applications.backend.allowedOrigins),
        AUTH_URL: "https://" + config.domains.primary + "/auth",
        OAUTH_REALM: "spezistudyplatform",
        OAUTH_CLIENT_ID: "spezistudyplatform",
        DB_HOST: config.project.name + "-db-rw",
        DB_NAME: config.project.name,
      },
    },

    "backend-deployment": {
      apiVersion: "apps/v1",
      kind: "Deployment",
      metadata: {
        name: config.project.name + "-backend",
        namespace: config.project.namespace,
        labels: {
          app: config.project.name + "-backend",
        },
        annotations: {
          "argocd.argoproj.io/sync-wave": "5",
        },
      },
      spec: {
        replicas: 1,
        strategy: {
          type: "Recreate",
        },
        selector: {
          matchLabels: {
            app: config.project.name + "-backend",
          },
        },
        template: {
          metadata: {
            labels: {
              app: config.project.name + "-backend",
            },
          },
          spec: {
            containers: [
              {
                name: config.project.name + "-backend-container",
                image: if config.environment.isLocal then "traefik/whoami:latest" else "gcr.io/spezistudyplatform-dev/spezi-web-service-template-backend:latest",
                imagePullPolicy: config.applications.backend.imagePullPolicy,
                resources: {
                  limits: {
                    memory: "2Gi",
                    cpu: "1",
                  },
                },
                ports: [
                  {
                    containerPort: if config.environment.isLocal then 80 else config.applications.backend.port,
                  },
                ],
                envFrom: if !config.environment.isLocal then [
                  {
                    configMapRef: {
                      name: config.project.name + "-backend-config",
                    },
                  },
                ] else [],
                env: if !config.environment.isLocal then [
                  {
                    name: "DB_USER",
                    valueFrom: {
                      secretKeyRef: {
                        name: config.project.name + "-postgres-credentials",
                        key: "username",
                      },
                    },
                  },
                  {
                    name: "DB_PASSWORD",
                    valueFrom: {
                      secretKeyRef: {
                        name: config.project.name + "-postgres-credentials",
                        key: "password",
                      },
                    },
                  },
                  {
                    name: "OAUTH_CLIENT_SECRET",
                    valueFrom: {
                      secretKeyRef: {
                        name: config.project.name + "-backend-secret",
                        key: "OAUTH_CLIENT_SECRET",
                      },
                    },
                  },
                ] else [],
              },
            ],
          },
        },
      },
    },

    "backend-service": {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        name: config.project.name + "-backend-service",
        namespace: config.project.namespace,
        annotations: {
          "argocd.argoproj.io/sync-wave": "5",
        },
      },
      spec: {
        selector: {
          app: config.project.name + "-backend",
        },
        ports: [
          {
            protocol: "TCP",
            port: config.applications.backend.port,
            targetPort: if config.environment.isLocal then 80 else config.applications.backend.port,
          },
        ],
      },
    },
}
