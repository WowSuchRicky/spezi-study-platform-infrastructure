# Local Development Setup with KIND

This guide explains how to set up a local development environment using KIND (Kubernetes in Docker).

## Prerequisites

*   [Docker](https://docs.docker.com/get-docker/)
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
*   [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
*   [helm](httpss://helm.sh/docs/intro/install/)

## Setup

1.  **Make the scripts executable:**

    ```bash
    chmod +x local-dev/setup.sh local-dev/cleanup.sh
    ```

2.  **Start the local Kubernetes cluster:**

    ```bash
    ./local-dev/setup.sh
    ```

    This script will:
    *   Create a KIND cluster.
    *   Prepare the Kubernetes manifests for local use.
    *   Install Traefik as an ingress controller.
    *   Deploy the application to the cluster.

3.  **Access the services:**

    The services will be available at `http://local.127.0.0.1.nip.io`.

    *   Frontend: `http://local.127.0.0.1.nip.io`
    *   Backend: `http://local.127.0.0.1.nip.io/backend`
    *   Keycloak: `http://local.127.0.0.1.nip.io/auth`
    *   Traefik Dashboard: `http://localhost/dashboard/`


## Teardown

To delete the local cluster and cleanup the generated files:

```bash
./local-dev/cleanup.sh
```
