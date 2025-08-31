{
  // Base configuration that can be customized per environment
  base:: {
    namespace: 'spezistudyplatform',
    domain: null, // Must be set by environment
    tlsSecretName: 'tls-secret',
    storageClass: null, // Must be set by environment
    loadBalancerIP: null, // Optional, set by environment if needed
    mode: 'PRODUCTION', // Default to production mode
    caCrt: null, // Must be set by environment
    
    // External Secrets configuration (disabled by default)
    externalSecrets: {
      enabled: false,
      provider: null, // 'vault' for local-dev, 'gcpsm' for production
      vault: {
        server: 'http://vault.vault.svc.cluster.local:8200',
        rootToken: 'dev-only-token', // Only for development
      },
      gcp: {
        projectId: null, // Must be set for production
        serviceAccountKeySecret: null, // Must be set for production
      },
    },
    
    // Validation function to ensure required values are set
    assert self.domain != null : 'domain must be set in environment config',
    assert self.storageClass != null : 'storageClass must be set in environment config',
    assert (self.mode == 'DEV' || self.caCrt != null) : 'caCrt must be set in production environment config',
  },
  
  // Production configuration
  prod:: self.base {
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
  
  // Local development configuration  
  localDev:: self.base {
    domain: 'spezi.172.20.117.44.nip.io',
    loadBalancerIP: '172.20.117.44', // Match nip.io domain
    storageClass: 'standard',
    mode: 'DEV',
    externalSecrets+: {
      enabled: true,
      provider: 'vault',
    },
  },
}