#!/bin/bash
# Dynamic IP detection script for local development
# Works across different OSes and network configurations

set -euo pipefail

# Function to detect the primary network interface IP
get_primary_ip() {
    local ip=""
    
    # Try different methods based on OS and network setup
    
    # Method 1: Check for WSL2 eth0 interface (common in WSL2)
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Method 2: Use route command (works on many Unix-like systems)
    if command -v route >/dev/null 2>&1; then
        # Get the IP of the default gateway interface
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            ip=$(ip route show default | awk '/default/ { print $9 }' | head -n1 2>/dev/null || true)
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            ip=$(route get default 2>/dev/null | grep interface | awk '{print $2}' | xargs -I{} ipconfig getifaddr {} 2>/dev/null || true)
        fi
        
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Method 3: Check common interface names
    local interfaces=("eth0" "en0" "wlan0" "wlp0s20f3" "enp0s3" "ens33")
    
    for iface in "${interfaces[@]}"; do
        if command -v ip >/dev/null 2>&1; then
            ip=$(ip addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -n1 || true)
        elif command -v ifconfig >/dev/null 2>&1; then
            ip=$(ifconfig "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -n1 || true)
        fi
        
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # Method 4: Use hostname -I (Linux)
    if command -v hostname >/dev/null 2>&1 && [[ "$OSTYPE" == "linux-gnu"* ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Method 5: Fall back to checking all interfaces
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -n1 || true)
    elif command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -n1 || true)
    fi
    
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi
    
    # If all methods fail, return a fallback
    echo "127.0.0.1"
    return 1
}

# Main execution
main() {
    local detected_ip
    detected_ip=$(get_primary_ip)
    
    if [[ "$detected_ip" == "127.0.0.1" ]]; then
        echo "Warning: Could not detect a valid network IP, falling back to localhost" >&2
        echo "This may not work properly for Kind clusters" >&2
    fi
    
    echo "$detected_ip"
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi