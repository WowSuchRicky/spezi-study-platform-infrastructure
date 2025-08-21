local baseConfig = import '../../lib/platform/config.libsonnet';

// Spezi Study Platform local development configuration
baseConfig.default {
  project: {
    name: 'spezistudyplatform',
    namespace: 'spezistudyplatform',
    displayName: 'Spezi Study Platform',
  },

  domains: {
    primary: std.extVar('LOCAL_IP') + '.nip.io',
    auth: std.extVar('LOCAL_IP') + '.nip.io/auth',
  },

  environment: {
    name: 'local-dev',
    mode: 'DEV',
    isDev: true,
    isLocal: true,
  },

  infrastructure: {
    cluster: {
      storageClass: 'local-path',
      ingressClass: 'traefik',
    },
    
    loadBalancer: {
      enabled: false,
      staticIP: null,
      type: 'ClusterIP',
      hostPorts: true,
    },

    tls: {
      issuer: 'selfsigned-issuer',
      staging: false,
      selfSigned: true,
    },

    database: {
      enablePodMonitor: false,
    },
  },

  applications: {
    backend: {
      port: 3003,
      imagePullPolicy: 'IfNotPresent',
      allowedOrigins: [
        'http://127.0.0.1',
        'http://localhost:5173',
      ],
    },
    
    frontend: {
      imagePullPolicy: 'IfNotPresent',
    },
  },

  auth: {
    oauth2Proxy: {
      insecureSkipVerify: true,
      cookieSecure: false,
      codeChallenge: true,
    },
  },

  features: {
    argocd: true,
    oauth2Proxy: true,
    sealedSecrets: false,
  },
}