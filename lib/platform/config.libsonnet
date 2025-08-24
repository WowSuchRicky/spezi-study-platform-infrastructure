{
  // Base configuration that can be customized per environment
  base:: {
    namespace: 'spezistudyplatform',
    domain: null, // Must be set by environment
    tlsSecretName: 'tls-secret',
    storageClass: null, // Must be set by environment
    loadBalancerIP: null, // Optional, set by environment if needed
    mode: 'PRODUCTION', // Default to production mode
    
    // Validation function to ensure required values are set
    assert self.domain != null : 'domain must be set in environment config',
    assert self.storageClass != null : 'storageClass must be set in environment config',
  },
  
  // Production configuration
  prod:: self.base {
    domain: 'platform.spezi.stanford.edu',
    loadBalancerIP: '34.168.131.83',
    storageClass: 'standard-rwo',
    mode: 'PRODUCTION',
  },
  
  // Local development configuration  
  localDev:: self.base {
    domain: 'spezi.local.dev',
    loadBalancerIP: null, // No static IP for local dev
    storageClass: 'standard',
    mode: 'DEV',
  },
}