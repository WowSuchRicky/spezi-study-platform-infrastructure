#!/bin/bash

set -e

info() {
    echo "INFO: $1"
}

TARGET_URL="http://local.127.0.0.1.nip.io"

info "Running functional test for Spezi Study Platform..."
info "Curling $TARGET_URL..."

HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "$TARGET_URL")

info "Received HTTP status: $HTTP_STATUS"

if [ "$HTTP_STATUS" -eq 302 ]; then
    info "Test PASSED: Received a 302 redirect, which is expected for an unauthenticated user."
    exit 0
elif [ "$HTTP_STATUS" -eq 000 ]; then
    info "Test FAILED: Received status 000, which indicates a connection error (e.g., connection reset)."
    exit 1
else
    info "Test FAILED: Expected a 302 redirect, but got $HTTP_STATUS."
    exit 1
fi
