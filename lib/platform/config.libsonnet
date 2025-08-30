{
  // Base configuration that can be customized per environment
  base:: {
    platform: {
      namespace: 'spezistudyplatform',
      domain: null, // Must be set by environment
      tlsSecretName: 'tls-secret',
      storageClass: null, // Must be set by environment
      loadBalancerIP: null, // Optional, set by environment if needed
      mode: 'PRODUCTION', // Default to production mode
      caCrt: null, // Must be set by environment
    },
    
    // External Secrets configuration
    externalSecrets: {
      enabled: false, // Disabled by default, enable in specific environments
      provider: null, // 'vault' for local-dev, 'gcpsm' for production
      vault: {
        server: 'http://vault.spezistudyplatform.svc.cluster.local:8200',
        rootToken: 'dev-only-token', // Only for development
      },
      gcp: {
        projectId: null, // Must be set for production
        serviceAccountKeySecret: null, // Must be set for production
      },
    },
    
    // Validation function to ensure required values are set
    assert self.platform.domain != null : 'platform.domain must be set in environment config',
    assert self.platform.storageClass != null : 'platform.storageClass must be set in environment config',
    assert (self.platform.mode == 'DEV' || self.platform.caCrt != null) : 'platform.caCrt must be set in production environment config',
  },
  
  // Production configuration
  prod:: self.base {
    platform+: {
      domain: 'platform.spezi.stanford.edu',
      loadBalancerIP: '34.168.131.83',
      storageClass: 'standard-rwo',
      mode: 'PRODUCTION',
      // TODO: Replace with actual production CA certificate
      caCrt: |||
        -----BEGIN CERTIFICATE-----
        REPLACE_WITH_PRODUCTION_CA_CERTIFICATE
        -----END CERTIFICATE-----
      |||,
    },
    externalSecrets+: {
      enabled: true,
      provider: 'gcpsm',
      gcp+: {
        projectId: 'spezistudyplatform-prod', // Update with actual project ID
        serviceAccountKeySecret: 'gcp-secret-manager-sa',
      },
    },
  },
  
  // Local development configuration  
  localDev:: self.base {
    platform+: {
      domain: 'spezi.172.20.117.44.nip.io',
      loadBalancerIP: '172.20.117.44', // Match nip.io domain
      storageClass: 'standard',
      mode: 'DEV',
    },
    externalSecrets+: {
      enabled: false,
      provider: 'vault',
    },
  },
}