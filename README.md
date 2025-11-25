# **⚙️ BigBlueButton (BBB) Server Setup Script**

This Bash script (`install.sh`) is designed to automate the initial configuration of an **Ubuntu 22.04 LTS (Jammy Jellyfish)** server and the installation of **BigBlueButton (BBB)**, ensuring all hardware and software requirements are met before proceeding with the main installation.

The execution is **semi-unattended**: it only requires initial interaction to enter configuration parameters and the new root password.

## **🚀 Installed Versions**

This script uses the official BigBlueButton installer (`bbb-install.sh` from `v3.0.x-release` branch) for the latest version compatible with Ubuntu 22.04.

| Component | Version |
| :---- | :---- |
| **Operating System** | Ubuntu 22.04 LTS (Jammy Jellyfish) |
| **BigBlueButton Core** | **3.0.16** (Targeting jammy-300) |
| **Front-end** | Greenlight **3.6.3** |
| **Container** | Docker CE (Official) |

## **🛠️ Critical Hardware Requirements (Minimum)**

The script verifies these requirements and stops the BBB installation if they are not met:

| Requirement | Minimum Value | Script Check |
| :---- | :---- | :---- |
| **CPU** | 8 cores | `nproc >= 8` |
| **Memory (RAM + Swap)** | 16 GB total | Total RAM + Total Swap >= 16GB |
| **Disk Space** | 360 GB free space | `df -BG / >= 360G` |
| **System** | Ubuntu 22.04 (Kernel 5.x/6.x) | `lsb_release` and `uname -r` |
| **Network** | Ports 80, 443 (TCP) and 16384-32768 (UDP) open. | UFW rule verification. |

## **💻 Script Usage**

### **1. Preparation**

Ensure you have a clean instance of **Ubuntu 22.04** and SSH access as root or a user with sudo privileges.

### **2. Execution**

Run the script directly from GitHub:

```bash
curl -s https://raw.githubusercontent.com/neoSmartness/BBB-SSS/main/install.sh | sudo bash
```

### **3. Interaction (Requested Data)**

The script will briefly stop at the beginning to request the following configuration parameters, which are mandatory for the BBB installation and initial security:

1.  **Full Subdomain:** (E.g.: `bbb.mycompany.com`)
2.  **Short Name for Hosts:** (E.g.: `bbbserver`)
3.  **Email Address:** (For the Let's Encrypt SSL certificate)
4.  **New SSH Port:** (E.g.: `2222`. If `22`, it is ignored. **Changing it is recommended**.)
5.  **New Root Password:** (Requested and confirmed securely)

## **📋 Process Steps (Detail)**

The script executes the following steps in an unattended manner, except for the initial data input:

| Step | Section | Action Performed |
| :---- | :---- | :---- |
| **1.** | Data Input | Requests and validates the critical configuration parameters. |
| **2.** | Initial Update | `apt update -y` and `apt upgrade -y` of the base system. |
| **3.** | Hosts Configuration | Sets the `127.0.1.1` entries in `/etc/hosts` with the **Subdomain** and **Short Name**. |
| **4.** | Hostname Configuration | Sets the server hostname to the **Subdomain** value. |
| **5.** | SSH Configuration | If the SSH port is different from 22, it changes it in `/etc/ssh/sshd_config` and restarts the SSH service. |
| **6.** | Firewall Configuration (UFW) | Installs UFW, allows ports 80, 443 (TCP), 16384-32768 (UDP) and the new SSH port, then enables UFW. |
| **7.** | Password Change | Sets the **New Root Password** securely. |
| **8.** | Docker Installation | Installs **Docker CE** from the official Docker repository (removes old versions/podman). |
| **9.** | Final Re-Update | `apt update -y` and `apt upgrade -y` to ensure Docker and its dependencies are updated. |
| **10.** | SWAP Configuration | Creates an **8 GB** `/swapfile`, enables it, and makes it permanent in `/etc/fstab`. Configures `vm.swappiness=10`. |
| **11.** | Locales Configuration | Verifies and sets the system locale to `en_US.UTF-8`, required by BBB. |
| **12.** | Final Verification | **Verifies all critical hardware and software requirements** (CPU, RAM, Disk, OS, Docker). If any critical check fails, the script stops here. |
| **13.** | BBB Installation | If verification was successful, executes the unattended BigBlueButton installation command with the Let's Encrypt certificate. |

## **📝 Logging**

The script automatically logs all output (stdout and stderr) to `/var/log/bbb-sss.log`. This is useful for debugging installation issues.

## **📜 License**

MIT License
