local baseConfig = import '../../lib/platform/config.libsonnet';

// Spezi Study Platform production configuration
baseConfig.default {
  project: {
    name: 'spezistudyplatform',
    namespace: 'spezistudyplatform',
    displayName: 'Spezi Study Platform',
  },

  domains: {
    primary: 'study.muci.sh',
    auth: 'study.muci.sh/auth',
  },

  environment: {
    name: 'production',
    mode: 'PROD',
    isDev: false,
    isLocal: false,
  },

  infrastructure: {
    cluster: {
      storageClass: 'standard-rwo',
      ingressClass: 'traefik',
    },
    
    loadBalancer: {
      enabled: true,
      staticIP: '34.168.131.83',
      type: 'LoadBalancer',
      hostPorts: false,
    },

    tls: {
      issuer: 'letsencrypt-prod',
      staging: false,
      selfSigned: false,
    },

    database: {
      enablePodMonitor: true,
    },
  },

  applications: {
    backend: {
      port: 3003,
      imagePullPolicy: 'Always',
      allowedOrigins: [
        'http://127.0.0.1',
        'http://localhost:5173',
      ],
    },
    
    frontend: {
      imagePullPolicy: 'Always',
    },
  },

  auth: {
    oauth2Proxy: {
      insecureSkipVerify: false,
      cookieSecure: true,
      codeChallenge: true,
    },
  },

  features: {
    argocd: true,
    oauth2Proxy: true,
    sealedSecrets: true,
  },
}