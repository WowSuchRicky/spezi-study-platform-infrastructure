{
  // Base configuration that can be customized per environment
  base:: {
    namespace: 'spezistudyplatform',
    domain: null, // Must be set by environment
    tlsSecretName: 'tls-secret',
    storageClass: 'local-path',
  },
  
  // Production configuration
  prod:: self.base {
    domain: 'your-production-domain.com', // Replace with actual domain
    loadBalancerIP: '34.168.131.83',
    storageClass: 'standard-rwo',
  },
  
  // Local development configuration
  localDev:: self.base {
    domain: 'spezi.127.0.0.1.nip.io',
    loadBalancerIP: null, // No static IP for local dev
  },
}