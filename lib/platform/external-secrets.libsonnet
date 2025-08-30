local k = import 'k.libsonnet';

{
  withConfig(config)::
    local namespace = config.platform.namespace;
    local externalSecrets = config.externalSecrets;
    
    // External Secrets Operator deployment
    local operator = {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'Application',
      metadata: {
        name: 'external-secrets-operator',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '10',
        },
      },
      spec: {
        project: 'default',
        source: {
          repoURL: 'https://charts.external-secrets.io',
          chart: 'external-secrets',
          targetRevision: '0.19.2',  // Use latest stable version
          helm: {
            parameters: [
              { name: 'installCRDs', value: 'true' },
              { name: 'crds.createClusterExternalSecret', value: 'true' },
              { name: 'crds.createClusterSecretStore', value: 'true' },
              { name: 'crds.createPushSecret', value: 'true' },
              { name: 'serviceMonitor.enabled', value: 'false' },
            ],
          },
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: 'external-secrets-system',
        },
        syncPolicy: {
          automated: {
            prune: true,
            selfHeal: true,
          },
          syncOptions: [
            'CreateNamespace=true',
            'ServerSideApply=true',
          ],
        },
      },
    };

    // HashiCorp Vault for local development
    local vault = if externalSecrets.provider == 'vault' then {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'Application',
      metadata: {
        name: 'vault',
        namespace: 'argocd',
        annotations: {
          'argocd.argoproj.io/sync-wave': '15',
        },
      },
      spec: {
        project: 'default',
        source: {
          repoURL: 'https://helm.releases.hashicorp.com',
          chart: 'vault',
          targetRevision: '0.30.1',
          helm: {
            parameters: [
              // Development mode - NOT for production
              { name: 'server.dev.enabled', value: 'true' },
              { name: 'server.dev.devRootToken', value: externalSecrets.vault.rootToken },
              { name: 'injector.enabled', value: 'false' },
              { name: 'ui.enabled', value: 'true' },
              { name: 'ui.serviceType', value: 'ClusterIP' },
              { name: 'server.dataStorage.enabled', value: 'false' },
              { name: 'server.auditStorage.enabled', value: 'false' },
            ],
          },
        },
        destination: {
          server: 'https://kubernetes.default.svc',
          namespace: namespace,
        },
        syncPolicy: {
          automated: {
            prune: true,
            selfHeal: true,
          },
        },
      },
    } else {};

    // ClusterSecretStore for Vault
    local secretStore = if externalSecrets.provider == 'vault' then {
      apiVersion: 'external-secrets.io/v1beta1',
      kind: 'ClusterSecretStore',
      metadata: {
        name: 'vault-backend',
        annotations: {
          'argocd.argoproj.io/sync-wave': '20',
        },
      },
      spec: {
        provider: {
          vault: {
            server: externalSecrets.vault.server,
            path: 'secret',
            version: 'v2',
            auth: {
              tokenSecretRef: {
                name: 'vault-token',
                key: 'token',
                namespace: namespace,
              },
            },
          },
        },
      },
    } else {};

    // Vault token secret
    local vaultTokenSecret = if externalSecrets.provider == 'vault' then {
      apiVersion: 'v1',
      kind: 'Secret',
      metadata: {
        name: 'vault-token',
        namespace: namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': '18',
        },
      },
      type: 'Opaque',
      data: {
        token: std.base64(externalSecrets.vault.rootToken),
      },
    } else {};

    // Namespace for external-secrets-system
    local externalSecretsNamespace = {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'external-secrets-system',
        annotations: {
          'argocd.argoproj.io/sync-wave': '5',
        },
      },
    };

    // Return all resources
    if externalSecrets.enabled then
      [externalSecretsNamespace, operator] + 
      (if externalSecrets.provider == 'vault' then [vault, vaultTokenSecret, secretStore] else [])
    else []
}