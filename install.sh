#!/bin/bash

# This script performs the initial configuration of an Ubuntu 22.04 server
# It is assumed that the script is run directly as the root user (or with sudo -i).

# --- 0. ROOT USER CHECK ---
if [ "$EUID" -ne 0 ]; then
  echo "--------------------------------------------------------"
  echo "!!! ERROR: Permission denied !!!"
  echo "Please run this script as root or with 'sudo bash'."
  echo "--------------------------------------------------------"
  exit 1
fi

# --- DATA INPUT FUNCTION (Interactive) ---
read_input() {
    echo "--- 1. DATA INPUT ---"
    # IMPORTANT: '< /dev/tty' is added to EACH read command to force reading
    # from the terminal, even when the script is executed via pipe (curl | bash).
    read -p "Enter the full subdomain (e.g., bbb.example.com): " SUBDOMAIN < /dev/tty
    read -p "Enter the short name for Hosts (e.g., bbbserver): " SHORTNAME < /dev/tty
    read -p "Enter your email address (e.g., admin@example.com): " EMAIL < /dev/tty
    read -p "Enter the new SSH port (e.g., 2222): " SSH_PORT < /dev/tty

    # Basic SSH port validation
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1024 ] || [ "$SSH_PORT" -gt 65535 ]; then
        echo "Invalid SSH port. Using default value 22."
        SSH_PORT="22"
    fi
    echo
}

# --- PASSWORD INPUT FUNCTION (Secure) ---
read_password() {
    # Password Request (Use 'read -s' for secure input)
    while true; do
        read -s -p "Enter the new password for the root user: " ROOT_PASSWORD < /dev/tty
        echo
        read -s -p "Confirm the root password: " ROOT_PASSWORD_CONFIRM < /dev/tty
        echo
        
        if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
            if [ -z "$ROOT_PASSWORD" ]; then
                echo "ERROR: Password cannot be empty. Please try again."
                continue
            fi
            break
        else
            echo "ERROR: Passwords do not match. Please try again."
        fi
    done
    echo "Password accepted."
    echo "--------------------------------------------------------"
}

# --- SWAP CREATION FUNCTION (Integrated) ---
setup_swap() {
    echo "--- 2. SWAP SPACE CONFIGURATION (8GB) ---"
    SWAPFILE="/swapfile"
    SWAPSIZE="8G"
    SWAPPINESS_VALUE=10

    if [ -f "$SWAPFILE" ]; then
        echo "Swap file already exists. Skipping creation."
        return 0
    fi

    echo "Creating ${SWAPSIZE} file..."
    fallocate -l "$SWAPSIZE" "$SWAPFILE"
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
    swapon "$SWAPFILE"

    # Persistence
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        echo "Swap file added to /etc/fstab."
    fi

    # Performance configuration (swappiness)
    if [ "$(sysctl -n vm.swappiness)" != "$SWAPPINESS_VALUE" ]; then
        sysctl vm.swappiness="$SWAPPINESS_VALUE"
        echo "vm.swappiness=${SWAPPINESS_VALUE}" > /etc/sysctl.d/99-swappiness.conf
        echo "Swappiness configured to ${SWAPPINESS_VALUE}."
    fi

    echo "Swap of ${SWAPSIZE} configured successfully. (Priority: ${SWAPPINESS_VALUE})"
    echo "--------------------------------------------------------"
}

# --- BIGBLUEBUTTON INSTALLATION FUNCTION (Includes Greenlight) ---
install_bbb() {
    echo "--- 14. STARTING BIGBLUEBUTTON AND GREENLIGHT INSTALLATION ---"
    
    # Note: bbb-install.sh uses the email for Let's Encrypt and configures Greenlight.
    
    echo "Executing BigBlueButton installation (version 2.7.x or higher):"
    
    # 1. Install GPG key and configure BBB repository
    # Installing BigBlueButton 3.0 (jammy-300) and Greenlight (-g) using the v3.0.x-release branch
    wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -v jammy-300 -s "$SUBDOMAIN" -e "$EMAIL" -g

    if [ $? -eq 0 ]; then
        echo "BigBlueButton 3.0.16 and Greenlight 3.6.3 installation completed successfully."
    else
        echo "ERROR: BigBlueButton installation failed. Check the logs."
        exit 1
    fi
    
    # 2. Get Greenlight administrator access URL
    echo "--- GREENLIGHT ACCESS INFORMATION ---"
    
    GL_ADMIN_EMAIL="$EMAIL"
    
    echo "To get Greenlight administrator credentials, you must check the output of the bbb-install.sh script."
    echo "The Greenlight access URL is: https://$SUBDOMAIN"
    echo "--------------------------------------------------------"
}

# --- REQUIREMENTS VERIFICATION FUNCTION ---
run_verification() {
    echo "--- 13. CRITICAL REQUIREMENTS VERIFICATION ---"
    VERIFICATION_PASSED=true
    
    # 1. Verify if Hostname is correct
    if [ "$(hostname)" != "$SHORTNAME" ]; then
        echo "FAIL: Current hostname ($(hostname)) does not match expected ($SHORTNAME)."
        VERIFICATION_PASSED=false
    else
        echo "SUCCESS: Hostname configured correctly."
    fi
    
    # 2. Verify Ubuntu version (22.04)
    if ! grep -q "22.04" /etc/os-release; then
        echo "FAIL: System is not Ubuntu 22.04."
        VERIFICATION_PASSED=false
    else
        echo "SUCCESS: Ubuntu version 22.04 detected."
    fi

    # 3. Verify kernel
    if [[ "$(uname -r)" != *"6.5"* ]]; then
        echo "WARNING: Kernel 6.5 is recommended for a better experience. Current kernel is $(uname -r)."
    fi

    # 4. Verify Docker
    if ! command -v docker &> /dev/null; then
        echo "FAIL: Docker is not installed."
        VERIFICATION_PASSED=false
    else
        echo "SUCCESS: Docker is installed."
    fi
    
    echo "--------------------------------------------------------"
    # Return verification status.
    if $VERIFICATION_PASSED; then
        return 0
    else
        return 1
    fi
}

# --- MAIN EXECUTION FUNCTION ---
main() {
    # Set DEBIAN_FRONTEND to noninteractive to suppress apt/debconf dialogs,
    # including kernel confirmation during upgrade.
    export DEBIAN_FRONTEND=noninteractive
    
    # 1. Request Data
    read_input
    read_password
    
    # 2. Configure SWAP
    setup_swap
    
    # 3. Update Root Password
    echo "--- 3. ROOT PASSWORD CONFIGURATION ---"
    echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd root 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Root password updated successfully."
    else
        echo "WARNING: Could not set root password (may not be available or system uses sudo)."
    fi
    echo "--------------------------------------------------------"

    # 4. Update Repositories and Install Initial Dependencies
    echo "--- 4. UPDATE AND INITIAL PACKAGES ---"
    # DEBIAN_FRONTEND=noninteractive should suppress kernel prompt here.
    apt update -y
    apt upgrade -y
    apt install -y curl gnupg2 software-properties-common wget apt-transport-https htop net-tools ntpdate ca-certificates
    echo "Update and initial packages completed."
    echo "--------------------------------------------------------"
    
    # 5. Hostname Configuration
    echo "--- 5. HOSTNAME CONFIGURATION ---"
    hostnamectl set-hostname "$SHORTNAME"
    echo "127.0.0.1       localhost" > /etc/hosts
    echo "127.0.0.1       $SHORTNAME" >> /etc/hosts
    echo "::1             ip6-localhost ip6-loopback" >> /etc/hosts
    echo "ff02::1         ip6-allnodes" >> /etc/hosts
    echo "ff02::2         ip6-allrouters" >> /etc/hosts
    
    # Configure MOTD
    echo "Welcome to BigBlueButton Server - Installed via BBB-SSS" > /etc/motd
    echo "--------------------------------------------------------"

    # 6. SSH Configuration
    echo "--- 6. SSH CONFIGURATION ---"
    if [ "$SSH_PORT" != "22" ]; then
        echo "Configuring SSH to use port $SSH_PORT..."
        # Backup sshd_config
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        # Uncomment Port if commented, or replace existing Port directive
        if grep -q "^#Port" /etc/ssh/sshd_config; then
            sed -i "s/^#Port.*/Port $SSH_PORT/" /etc/ssh/sshd_config
        elif grep -q "^Port" /etc/ssh/sshd_config; then
            sed -i "s/^Port.*/Port $SSH_PORT/" /etc/ssh/sshd_config
        else
            echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
        fi
        
        echo "Restarting SSH service..."
        systemctl restart sshd
        echo "SSH configured on port $SSH_PORT."
    else
        echo "SSH port remains at default (22)."
    fi
    echo "--------------------------------------------------------"

    # 6. Firewall Configuration (UFW)
    echo "--- 6. FIREWALL CONFIGURATION (UFW) ---"
    ufw allow "$SSH_PORT"/tcp comment 'SSH New Port'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    # Ports for BBB/WebRTC: UDP 16384-32768
    ufw allow 16384:32768/udp comment 'BigBlueButton/WebRTC'
    # Enable UFW, if not active
    if ! ufw status | grep -q "active"; then
        ufw --force enable
        echo "UFW Firewall enabled and BBB ports configured."
    else
        ufw reload
        echo "UFW Firewall updated."
    fi
    echo "--------------------------------------------------------"

    # 7. Docker Installation (Based on docker.sh)
    echo "--- 7. DOCKER INSTALLATION ---"
    
    # 7.1 Remove old versions
    echo "Removing old Docker versions..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt remove -y $pkg; done
    apt autoremove -y
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd

    # 7.2 Add Docker official repository
    echo "Configuring Docker repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      \"$(. /etc/os-release && echo \"$VERSION_CODENAME\")\" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 7.3 Install Docker Engine
    echo "Installing Docker Engine, CLI and Compose..."
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 7.4 Post-installation steps (Group)
    if ! grep -q "^docker:" /etc/group; then
        groupadd docker
    fi
    usermod -aG docker "$USER" # This might be root, which is fine
    
    # 7.5 Verify Docker
    if command -v docker &> /dev/null && docker info >/dev/null 2>&1; then
        echo "Docker installed and running."
    else
        echo "ERROR: Failed to install Docker. BBB installation cannot continue."
        exit 1
    fi
    echo "--------------------------------------------------------"
    
    # 8. Enable IPv4 Forwarding
    echo "--- 8. ENABLING IPv4 FORWARDING ---"
    sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -p
    echo "IPv4 forwarding enabled and persistent."
    echo "--------------------------------------------------------"

    # 9. NTP Configuration (Time Synchronization)
    echo "--- 9. NTP CONFIGURATION ---"
    ntpdate pool.ntp.org
    timedatectl set-ntp true
    echo "Time synchronization configured."
    echo "--------------------------------------------------------"

    # 10. Re-Update System (Post-Docker)
    echo "--- 10. FINAL RE-UPDATE ---"
    apt update -y
    apt upgrade -y
    echo "Final update completed."
    echo "--------------------------------------------------------"
    
    # 11. VERIFICATION AND LOCALES CONFIGURATION
    echo "--- 12. LOCALES CONFIGURATION ---"

    CURRENT_LANG=$(cat /etc/default/locale 2>/dev/null | grep -E '^LANG=' | cut -d'=' -f2 | tr -d '\"')
    EXPECTED_LANG="en_US.UTF-8"

    if [ "$CURRENT_LANG" = "$EXPECTED_LANG" ]; then
        echo "Current LANG ($CURRENT_LANG) already matches expected ($EXPECTED_LANG). No changes required."
    else
        echo "Current LANG ($CURRENT_LANG) does not match expected ($EXPECTED_LANG)."
        echo "Installing language packages and configuring LANG to en_US.UTF-8..."
        
        # Install necessary language pack
        apt install -y language-pack-en
        
        # Configure new locale
        update-locale LANG="$EXPECTED_LANG"
        
        echo "LANG configured to $EXPECTED_LANG. Will be effective on next reboot or new session."
    fi
    echo "--------------------------------------------------------"
    
    # 12. Run Final Verifications and decide whether to install BBB
    if run_verification; then
        echo "[ VERIFICATION RESULT: SUCCESS ] All critical BBB requirements are met."
        install_bbb # Internal step number adjusts to 14
    else
        echo "[ VERIFICATION RESULT: FAIL ] Critical requirements for BigBlueButton installation are missing."
        echo "BBB Installation SKIPPED."
        exit 1
    fi
    
    echo "========================================================"
    echo "== CONFIGURATION AND INSTALLATION COMPLETED =="
    echo "========================================================"
    echo "To make locale and hostname settings permanent, it is recommended to reboot the server."
    echo "Suggested command: reboot"
    echo ""

}

# Start main function
main
