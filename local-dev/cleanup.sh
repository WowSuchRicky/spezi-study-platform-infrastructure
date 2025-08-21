#!/bin/bash

set -e

KIND_CLUSTER_NAME="spezi-study-platform"
LOCAL_DEV_DIR="./local-dev"

echo "INFO: Deleting KIND cluster '$KIND_CLUSTER_NAME'..."
kind delete cluster --name "$KIND_CLUSTER_NAME"

echo "INFO: Removing local manifests..."
rm -rf "$LOCAL_DEV_DIR/kube"

echo "INFO: Cleanup complete."
