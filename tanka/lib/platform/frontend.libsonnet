
function(config) 
{
    "frontend-configmap": {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: config.project.name + "-frontend-config",
        namespace: config.project.namespace,
        annotations: {
          "argocd.argoproj.io/sync-wave": "6",
        },
      },
      data: {
        VITE_API_BASE: "https://" + config.domains.primary + "/",
        OAUTH_AUTHORITY: "https://" + config.domains.primary + "/auth/realms/spezistudyplatform",
        OAUTH_REDIRECT_URI: "https://" + config.domains.primary,
        OAUTH_CLIENT_ID: "spezistudyplatform",
      },
    },

    "frontend-deployment": {
      apiVersion: "apps/v1",
      kind: "Deployment",
      metadata: {
        name: config.project.name + "-frontend",
        namespace: config.project.namespace,
        labels: {
          app: config.project.name + "-frontend",
        },
        annotations: {
          "argocd.argoproj.io/sync-wave": "6",
        },
      },
      spec: {
        replicas: 1,
        strategy: {
          type: "Recreate",
        },
        selector: {
          matchLabels: {
            app: config.project.name + "-frontend",
          },
        },
        template: {
          metadata: {
            labels: {
              app: config.project.name + "-frontend",
            },
          },
          spec: {
            containers: [
              {
                name: config.project.name + "-frontend-container",
                image: "traefik/whoami:latest", // TODO: this should obviously be a frontend container once we have one
                imagePullPolicy: config.applications.frontend.imagePullPolicy,
                resources: {
                  limits: {
                    memory: "1Gi",
                    cpu: "100m",
                  },
                },
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
                envFrom: [
                  {
                    configMapRef: {
                      name: config.project.name + "-frontend-config",
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    },

    "frontend-service": {
      apiVersion: "v1",
      kind: "Service",
      metadata: {
        name: config.project.name + "-frontend-service",
        namespace: config.project.namespace,
        annotations: {
          "argocd.argoproj.io/sync-wave": "6",
        },
      },
      spec: {
        selector: {
          app: config.project.name + "-frontend",
        },
        ports: [
          {
            protocol: "TCP",
            port: 80,
            targetPort: 80,
            name: "main",
          },
        ],
        type: "ClusterIP",
      },
    },
}
