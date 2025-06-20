#!/bin/bash

# Push commands in the background, when the script exits, the commands will exit too
kubectl --namespace spezistudyplatform port-forward service/spezistudyplatform-db-rw 5432:5432 & \
kubectl --namespace spezistudyplatform port-forward service/spezistudyplatform-redis-master 6379:6379 & \

echo "Press CTRL-C to stop port forwarding and exit the script"
wait