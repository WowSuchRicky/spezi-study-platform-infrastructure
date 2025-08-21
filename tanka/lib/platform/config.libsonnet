{
  // Default configuration structure that can be overridden per environment
  default:: {
    // Project-specific settings - these should be templated/overridden
    project: {
      name: 'myproject',          // Project name (used in resource names)
      namespace: 'myproject',     // Kubernetes namespace
      displayName: 'My Project', // Human readable name
    },

    // Domain configuration  
    domains: {
      primary: 'example.com',     // Primary domain
      auth: 'example.com/auth',   // Auth endpoint
    },

    // Environment-specific overrides
    environment: {
      name: 'production',         // Environment name
      mode: 'PROD',              // Application mode
      isDev: false,              // Development flag
      isLocal: false,            // Local development flag
    },

    // Infrastructure configuration
    infrastructure: {
      // Kubernetes cluster
      cluster: {
        storageClass: 'standard-rwo',
        ingressClass: 'traefik',
      },
      
      // Load balancer / ingress
      loadBalancer: {
        enabled: true,
        staticIP: null,
        type: 'LoadBalancer',
        hostPorts: false,
      },

      // TLS/Certificate configuration
      tls: {
        issuer: 'letsencrypt-prod',
        staging: false,
        selfSigned: false,
      },

      // Database
      database: {
        enablePodMonitor: true,
        // host, name, user will be computed as: config.project.name + '-db-rw', etc.
      },
    },

    // Application configuration
    applications: {
      backend: {
        port: 3003,
        imagePullPolicy: 'Always',
        allowedOrigins: [
          'http://127.0.0.1',
          'http://localhost:5173',
          // Primary domain origins will be computed as: 'https://' + config.domains.primary, etc.
        ],
      },
      
      frontend: {
        imagePullPolicy: 'Always',
      },
    },

    // Authentication configuration
    auth: {
      // realm and clientId will be computed as: config.project.name
      oauth2Proxy: {
        insecureSkipVerify: false,
        cookieSecure: true,
        codeChallenge: true,
        // whitelist will be computed from config.domains.primary
      },
    },

    // Feature flags
    features: {
      argocd: true,              // Include ArgoCD
      oauth2Proxy: true,         // Include OAuth2 Proxy
      sealedSecrets: true,       // Use sealed secrets vs plain secrets
    },
  },
}