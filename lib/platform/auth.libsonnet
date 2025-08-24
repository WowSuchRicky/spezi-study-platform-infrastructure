{
  withConfig(config)::
    local keycloak = import './keycloak.libsonnet';
    local oauth2Proxy = import './oauth2-proxy.libsonnet';
    local authIngress = import './auth-ingress.libsonnet';
    
    // Combine all auth-related components
    // keycloak and oauth2Proxy return arrays, authIngress returns object
    local keycloakResources = keycloak.withConfig(config);
    local oauth2ProxyResources = oauth2Proxy.withConfig(config);
    local authIngressResources = std.objectValues(authIngress.withConfig(config));
    
    // Return combined array of all resources
    keycloakResources + oauth2ProxyResources + authIngressResources,
}