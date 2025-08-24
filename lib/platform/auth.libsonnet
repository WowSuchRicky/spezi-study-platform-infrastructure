{
  withConfig(config)::
    local keycloak = import './keycloak.libsonnet';
    local oauth2Proxy = import './oauth2-proxy.libsonnet';
    local authIngress = import './auth-ingress.libsonnet';
    
    // Combine all auth-related components
    keycloak.withConfig(config) +
    oauth2Proxy.withConfig(config) +
    authIngress.withConfig(config),
}