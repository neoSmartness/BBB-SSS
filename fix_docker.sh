#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "--- FIX DOCKER SCRIPT ---"
echo "This script will aggressively remove old docker-compose binaries and retry Greenlight installation."

# Input required variables
read -p "Enter the full subdomain (e.g., bbb.example.com): " SUBDOMAIN
read -p "Enter your email address (e.g., admin@example.com): " EMAIL

if [ -z "$SUBDOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "Error: Subdomain and Email are required."
    exit 1
fi

# Function for aggressive removal
remove_docker_compose() {
    local path="$1"
    if [ -f "$path" ]; then
        echo "Found $path. Attempting removal..."
        
        # Try standard removal
        rm -v "$path"
        
        # Check if it still exists
        if [ -f "$path" ]; then
            echo "Standard removal failed. Checking for immutable flag..."
            chattr -i "$path"
            rm -v "$path"
        fi
        
        # Check again
        if [ -f "$path" ]; then
            echo "Still exists. Attempting to truncate..."
            truncate -s 0 "$path"
            rm -v "$path"
        fi
        
        # Final check
        if [ -f "$path" ]; then
            echo "CRITICAL ERROR: Could not remove $path. Please manually investigate."
            exit 1
        else
            echo "$path removed successfully."
        fi
    else
        echo "$path not found."
    fi
}

# 1. Aggressive Removal
echo "--- 1. REMOVING OLD BINARIES ---"
remove_docker_compose "/usr/local/bin/docker-compose"
remove_docker_compose "/usr/bin/docker-compose"

# 2. Verify Removal
echo "--- 2. VERIFYING REMOVAL ---"
if command -v docker-compose &> /dev/null; then
    VERSION=$(docker-compose --version)
    echo "Warning: docker-compose still found in path: $VERSION"
    echo "Location: $(which docker-compose)"
    
    # Check if it's the new plugin wrapper or the old binary
    if [[ "$VERSION" == *"version 1."* ]]; then
        echo "CRITICAL: Old version 1.x still detected. Aborting installation to prevent errors."
        exit 1
    else
        echo "Detected version seems to be modern (not 1.x). Proceeding..."
    fi
else
    echo "docker-compose not found in PATH (Good, we want to use 'docker compose' plugin)."
fi

# 3. Retry Installation
echo "--- 3. RETRYING INSTALLATION ---"
echo "Executing bbb-install.sh..."
wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -v jammy-300 -s "$SUBDOMAIN" -e "$EMAIL" -g

echo "--------------------------------------------------------"
echo "Fix script completed."
