{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local cnpgManifests = kustomize.build('../../kustomize/cloudnative-pg/');
    // Convert to array if it's an object, otherwise use as is
    local manifestArray = if std.isArray(cnpgManifests) then cnpgManifests else std.objectValues(cnpgManifests);
    local filtered = [
      resource
      for resource in manifestArray
      if resource.kind != 'CustomResourceDefinition'
    ];
    local allManifests = filtered + [
      {
        apiVersion: 'postgresql.cnpg.io/v1',
        kind: 'Cluster',
        metadata: {
          name: 'spezistudyplatform-db',
          namespace: config.namespace,
        },
        spec: {
          imageName: 'ghcr.io/cloudnative-pg/postgresql:17-bullseye',
          instances: 1,
          storage: {
            size: '1Gi',
          },
          monitoring: {
            enablePodMonitor: true,
          },
          enableSuperuserAccess: true,
          bootstrap: {
            initdb: {
              database: 'spezistudyplatform',
              owner: 'spezistudyplatform',
              secret: {
                name: 'spezistudyplatform-postgres-credentials',
              },
            },
          },
        },
      },
      {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'spezistudyplatform-postgres-credentials',
          namespace: config.namespace,
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          refreshInterval: '15s',
          secretStoreRef: {
            name: if config.externalSecrets.provider == 'gcpsm' then 'gcpsm-secret-store' else 'vault-backend',
            kind: 'ClusterSecretStore',
          },
          target: {
            name: 'spezistudyplatform-postgres-credentials',
            creationPolicy: 'Owner',
            template: {
              type: 'kubernetes.io/basic-auth',
              engineVersion: 'v2',
              data: {
                username: '{{ .username }}',
                password: '{{ .password }}',
              },
            },
          },
          data: [
            {
              secretKey: 'username',
              remoteRef: {
                key: 'spezistudyplatform-postgres-credentials',
                property: 'username',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
            {
              secretKey: 'password',
              remoteRef: {
                key: 'spezistudyplatform-postgres-credentials',
                property: 'password',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
          ],
        },
      },
      // PushSecret for postgres password (only for GCP Secret Manager)
      if config.externalSecrets.provider == 'gcpsm' then {
        apiVersion: 'external-secrets.io/v1alpha1',
        kind: 'PushSecret',
        metadata: {
          name: 'postgres-password-push-secret',
          namespace: 'external-secrets-system',
        },
        spec: {
          updatePolicy: 'IfNotExists',
          refreshInterval: '24h',
          secretStoreRefs: [
            {
              name: 'gcpsm-secret-store',
              kind: 'ClusterSecretStore',
            },
          ],
          selector: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'Password',
              name: 'db-password-generator',
            },
          },
          data: [
            {
              match: {
                secretKey: 'password',
                remoteRef: {
                  remoteKey: 'spezistudyplatform-postgres-credentials',
                  property: 'password',
                },
              },
            },
          ],
        },
      } else {},
      // PushSecret for postgres username (static value, only for GCP Secret Manager)
      if config.externalSecrets.provider == 'gcpsm' then {
        apiVersion: 'external-secrets.io/v1alpha1',
        kind: 'PushSecret',
        metadata: {
          name: 'postgres-username-push-secret',
          namespace: 'external-secrets-system',
        },
        spec: {
          updatePolicy: 'IfNotExists',
          refreshInterval: '24h',
          secretStoreRefs: [
            {
              name: 'gcpsm-secret-store',
              kind: 'ClusterSecretStore',
            },
          ],
          selector: {
            generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: 'Fake',
              name: 'postgres-username-generator',
            },
          },
          data: [
            {
              match: {
                secretKey: 'username',
                remoteRef: {
                  remoteKey: 'spezistudyplatform-postgres-credentials',
                  property: 'username',
                },
              },
            },
          ],
        },
      } else {},
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in allManifests
    },
}