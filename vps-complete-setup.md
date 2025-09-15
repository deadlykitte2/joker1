# Complete VPS OpenVPN Server Setup Guide

## Overview

This guide provides two methods to set up a bulletproof VPS OpenVPN server for MikroTik remote access management:

1. **Method A: One-Click Deployment (Recommended)** - Automated script that sets up everything
2. **Method B: Manual Step-by-Step** - Traditional manual installation

**What you'll achieve:**
- OpenVPN server with MikroTik compatibility (TCP, AES-256-CBC, SHA1)
- Support for unlimited MikroTik routers with automatic management
- Direct remote access (Winbox, WebFig, SSH, API) without VPN client
- Bulletproof static IP assignment with automatic retry
- Dynamic NAT rules (no hardcoded IPs)
- Complete persistence across server reboots
- Web-based client management system
- Automatic expiration and billing support
- Professional customer onboarding experience

## Method A: One-Click Deployment (Recommended)

### Prerequisites
- Fresh Ubuntu VPS (20.04+ or 22.04+)
- Root access to the VPS
- Public IP address

### Step 1: Download and Run Deployment Script

```bash
# Connect to your VPS as root
ssh root@YOUR_VPS_IP

# Download the one-click deployment script
curl -O https://raw.githubusercontent.com/yourdomain/mikrotik-remote-access/main/vps-one-click-deploy.sh

# Make it executable
chmod +x vps-one-click-deploy.sh

# Run the deployment (takes 5-10 minutes)
./vps-one-click-deploy.sh
```

### What the Script Does Automatically

The deployment script performs these actions:

1. **System Setup** - Updates packages, installs essentials, enables IP forwarding
2. **Firewall Configuration** - Sets up UFW with proper ports
3. **OpenVPN Installation** - Installs and configures with MikroTik compatibility
4. **Service Fixes** - Resolves common OpenVPN service issues
5. **MikroTik Compatibility** - Configures AES-256-CBC, SHA1, TLS 1.0, legacy provider
6. **Dynamic NAT Manager** - Creates bulletproof NAT rule system (no hardcoded IPs)
7. **IP Reporting System** - PHP scripts for real-time IP monitoring
8. **Web Server Setup** - Nginx with PHP for client management
9. **Management Scripts** - All client creation and monitoring tools
10. **System Persistence** - Ensures everything survives reboots

### Step 2: Create Your First Client

After deployment completes:

```bash
# Create a test client
create-mikrotik-autoconfig customer-test 10.8.0.10 8300 8090 22050

# This creates:
# - Client certificates
# - Static IP assignment (10.8.0.10)
# - Port assignments (Winbox: 8300, WebFig: 8090, SSH: 22050, API: 9300, API-SSL: 9301)
# - RouterOS 6 & 7 auto-config scripts
# - Customer instruction webpage
# - Dynamic NAT rules
```

### Step 3: Send Customer the Link

The script outputs a customer link like:
```
http://YOUR_VPS_IP/clients/customer-test/instructions.html
```

Customer just:
1. Opens the webpage
2. Downloads the appropriate RouterOS script
3. Uploads to MikroTik and runs `/import setup-ros6.rsc`
4. Gets immediate remote access

### Step 4: Monitor and Manage

```bash
# Check client connections
check-client-ips

# Verify system health
verify-system-persistence

# Rebuild NAT rules if needed
fix-all-nat-rules

# View deployment summary
cat /root/deployment-summary.txt
```

### Benefits of One-Click Deployment

✅ **5-minute setup** instead of 2+ hours manual work  
✅ **Zero configuration errors** - all settings tested and proven  
✅ **Bulletproof IP assignment** - multiple enforcement methods  
✅ **Dynamic scaling** - supports unlimited clients automatically  
✅ **Professional customer experience** - automated onboarding  
✅ **Complete persistence** - survives reboots and updates  
✅ **Built-in monitoring** - real-time client status  
✅ **Future-proof** - includes all latest fixes and features  

### Deployment Script Features

The `vps-one-click-deploy.sh` script includes:

- **Automated OpenVPN installation** with optimal MikroTik settings
- **Service conflict resolution** (fixes common systemd issues)
- **Certificate management** with proper file paths
- **Compatibility layers** for RouterOS 6.49.10+ and RouterOS 7.x
- **Dynamic NAT system** that scales to unlimited clients
- **IP verification and retry** system for bulletproof connections
- **Web server with PHP** for client management and reporting
- **Persistence configuration** for all services and rules
- **Health monitoring** and verification scripts
- **Professional customer onboarding** system

---

## Method B: Manual Step-by-Step Installation

*Use this method if you prefer manual control or need to understand each step. For most users, Method A (One-Click Deployment) is recommended.*

### Part 1: Initial VPS Setup

### Step 1: Connect to VPS and Verify System

```bash
# Connect to your VPS
ssh root@16.28.86.103

# Check OS version
cat /etc/os-release
```

**Expected output:** Ubuntu 24.04.3 LTS (Noble Numbat)

### Step 2: System Update and Essential Packages

```bash
# Update system packages
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget nano ufw fail2ban htop net-tools

# Enable IP forwarding (critical for VPN routing)
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
```

### Step 3: Basic Firewall Setup

```bash
# Configure UFW firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 1194/tcp
ufw --force enable
ufw status
```

## Part 2: OpenVPN Server Installation

### Step 4: Download and Run OpenVPN Installation Script

```bash
# Download the proven OpenVPN installer
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

# Run the installer
./openvpn-install.sh
```

**Installation Options (EXACT settings that work):**
- IP address: [Accept default - your VPS IP]
- IPv6 support: `n` (No)
- Port: `1194`
- Protocol: `TCP` (Important: TCP works better with MikroTik)
- DNS: `3` (Cloudflare)
- Compression: `n` (No)
- Customized encryption: `n` (No)
- First client name: `mikrotik-test`
- Client password: Press Enter (no password)

### Step 5: Verify OpenVPN Installation

```bash
# Check OpenVPN service status
systemctl status openvpn-server@server --no-pager

# Verify port is listening
netstat -tuln | grep 1194

# Check client configuration file was created
cat /root/mikrotik-test.ovpn
```

**Expected results:**
- Service should be `active (running)`
- Port 1194 should be listening on TCP
- Client .ovpn file should exist

## Part 3: OpenVPN Server Configuration for MikroTik Compatibility

### Step 6: Fix OpenVPN Service Issues (if needed)

If the service shows as `inactive (dead)` but port 1194 is listening:

```bash
# Check for conflicting services
systemctl status openvpn@server
systemctl stop openvpn@server
systemctl disable openvpn@server

# Ensure correct service is running
systemctl start openvpn-server@server
systemctl enable openvpn-server@server
systemctl status openvpn-server@server
```

### Step 7: Fix File Paths (Critical Fix)

The installer sometimes puts files in wrong locations. Fix this:

```bash
# Copy configuration and certificates to expected location
cp /etc/openvpn/server.conf /etc/openvpn/server/server.conf
cp /etc/openvpn/ca.crt /etc/openvpn/server/
cp /etc/openvpn/server_*.crt /etc/openvpn/server/
cp /etc/openvpn/server_*.key /etc/openvpn/server/
cp /etc/openvpn/tls-crypt.key /etc/openvpn/server/ 2>/dev/null || true

# Generate missing CRL file
cd /etc/openvpn/easy-rsa
./easyrsa gen-crl
cp -f pki/crl.pem /etc/openvpn/server/crl.pem
chmod 644 /etc/openvpn/server/crl.pem
```

### Step 8: Configure MikroTik Compatibility Settings

```bash
# Edit server configuration for MikroTik compatibility
cd /etc/openvpn/server

# Remove incompatible settings
sed -i '/^ncp-disable/d; /^ncp-ciphers/d; /^tls-crypt/d; /^tls-cipher/d; /^tls-auth/d' server.conf

# Set MikroTik-compatible cipher and auth
sed -i 's/^auth .*/auth SHA1/' server.conf
sed -i 's/^cipher .*/cipher AES-256-CBC/' server.conf

# Add compatibility settings for RouterOS 6.49.10 and newer
cat >> server.conf << 'EOF'

# MikroTik RouterOS compatibility
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
tls-version-min 1.0
compat-mode 2.4.0
providers legacy default

# Enable client-config-dir for static IPs
client-config-dir /etc/openvpn/server/ccd
EOF

# Create client-config directory
mkdir -p /etc/openvpn/server/ccd
```

### Step 9: Restart and Verify OpenVPN Server

```bash
# Restart OpenVPN server
systemctl restart openvpn-server@server

# Verify service is running correctly
systemctl status openvpn-server@server --no-pager

# Check logs for any errors
journalctl -u openvpn-server@server -n 20 --no-pager

# Verify port is still listening
ss -tlpn | grep 1194
```

## Part 4: Client Management Setup

### Step 10: Create Client Management Scripts

```bash
# Create script to add new MikroTik clients
cat > /usr/local/bin/add-mikrotik-client << 'EOF'
#!/bin/bash
CLIENT_NAME=$1
if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: add-mikrotik-client <client_name>"
    exit 1
fi
cd /root
./openvpn-install.sh
EOF
chmod +x /usr/local/bin/add-mikrotik-client

# Create OpenVPN status script
cat > /usr/local/bin/openvpn-status << 'EOF'
#!/bin/bash
echo "=== OpenVPN Server Status ==="
systemctl status openvpn-server@server --no-pager
echo -e "\n=== Port Status ==="
netstat -tuln | grep 1194
echo -e "\n=== Connected Clients ==="
cat /etc/openvpn/server/openvpn-status.log 2>/dev/null || echo "No clients connected yet"
EOF
chmod +x /usr/local/bin/openvpn-status
```

## Part 5: First Client Setup (Test Router)

### Step 11: Create First Client Certificate

```bash
# Go to easy-rsa directory (correct path)
cd /etc/openvpn/easy-rsa

# Create client certificate
./easyrsa build-client-full mikrotik-client-02 nopass

# Prepare client files for download
mkdir -p /root/mikrotik-client-02
cp /etc/openvpn/server/ca.crt /root/mikrotik-client-02/
cp pki/issued/mikrotik-client-02.crt /root/mikrotik-client-02/
cp pki/private/mikrotik-client-02.key /root/mikrotik-client-02/

# Verify files are ready
ls -la /root/mikrotik-client-02/
```

### Step 12: Set Static VPN IP (Optional)

```bash
# Assign static VPN IP to client
echo "ifconfig-push 10.8.0.3 255.255.255.0" > /etc/openvpn/server/ccd/mikrotik-client-02

# Restart OpenVPN to apply CCD
systemctl restart openvpn-server@server
```

### Step 13: Set Up Port Forwarding for Remote Access

```bash
# Add DNAT rules (port forwarding)
iptables -t nat -A PREROUTING -p tcp --dport 8291 -j DNAT --to-destination 10.8.0.3:8291
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.8.0.3:80
iptables -t nat -A PREROUTING -p tcp --dport 22022 -j DNAT --to-destination 10.8.0.3:22

# Add SNAT rules (source NAT - CRITICAL for MikroTik to accept connections)
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 8291 -j SNAT --to-source 10.8.0.1
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 80 -j SNAT --to-source 10.8.0.1
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 22 -j SNAT --to-source 10.8.0.1

# Open firewall ports
ufw allow 8291/tcp
ufw allow 8080/tcp
ufw allow 22022/tcp

# Save iptables rules
iptables-save > /etc/iptables/rules.v4
```

## Part 6: Download and Configure MikroTik

### Step 14: Download Client Certificates

**On your local computer:**

```bash
# Create directory
mkdir ~/Desktop/mikrotik-client-02

# Download certificates individually (this method works reliably)
scp root@16.28.86.103:/root/mikrotik-client-02/ca.crt ~/Desktop/mikrotik-client-02/
scp root@16.28.86.103:/root/mikrotik-client-02/mikrotik-client-02.crt ~/Desktop/mikrotik-client-02/
scp root@16.28.86.103:/root/mikrotik-client-02/mikrotik-client-02.key ~/Desktop/mikrotik-client-02/

# Verify download
ls -la ~/Desktop/mikrotik-client-02/
```

### Step 15: Configure MikroTik Router

**Upload certificates via Winbox Files menu, then in MikroTik terminal:**

#### For RouterOS 6 (6.49.x):

```bash
# Import certificates
/certificate import file-name=ca.crt passphrase=""
/certificate import file-name=mikrotik-client-02.crt passphrase=""
/certificate import file-name=mikrotik-client-02.key passphrase=""

# Verify certificates (look for K flag on private key)
/certificate print

# Create OpenVPN client
/interface ovpn-client add name=ovpn-to-vps \
  connect-to=16.28.86.103 port=1194 mode=ip \
  user=mikrotik-client-02 password="" \
  auth=sha1 cipher=aes256 \
  certificate=mikrotik-client-02.crt_0 \
  verify-server-certificate=no add-default-route=no disabled=no

# Configure services (restrict to VPS tunnel IP for security)
/ip service set winbox disabled=no port=8291 address=10.8.0.1
/ip service set www disabled=no port=80 address=10.8.0.1
/ip service set ssh disabled=no port=22 address=10.8.0.1

# Add firewall rules
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8291 action=accept place-before=0 comment="Winbox via VPS"
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=80 action=accept place-before=0 comment="WebFig via VPS"
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=22 action=accept place-before=0 comment="SSH via VPS"
```

#### For RouterOS 7:

```bash
# Import certificates (same as RouterOS 6)
/certificate import file-name=ca.crt passphrase=""
/certificate import file-name=mikrotik-client-02.crt passphrase=""
/certificate import file-name=mikrotik-client-02.key passphrase=""

# Create OpenVPN client (note forward slashes and cipher change)
/interface/ovpn-client/add name=ovpn-to-vps \
  connect-to=16.28.86.103 port=1194 mode=ip \
  user=mikrotik-client-02 password="" \
  auth=sha1 cipher=aes256-cbc \
  certificate=mikrotik-client-02.crt_0 \
  verify-server-certificate=no add-default-route=no disabled=no

# Configure services (forward slash syntax)
/ip/service/set winbox disabled=no port=8291 address=10.8.0.1
/ip/service/set www disabled=no port=80 address=10.8.0.1
/ip/service/set ssh disabled=no port=22 address=10.8.0.1

# Add firewall rules (forward slash syntax)
/ip/firewall/filter/add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8291 action=accept place-before=0 comment="Winbox via VPS"
/ip/firewall/filter/add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=80 action=accept place-before=0 comment="WebFig via VPS"
/ip/firewall/filter/add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=22 action=accept place-before=0 comment="SSH via VPS"
```

### Step 16: Verify Connection

#### RouterOS 6:
```bash
/interface ovpn-client print status
/ip address print where interface=ovpn-to-vps
/log print where topics~"ovpn"
```

#### RouterOS 7:
```bash
/interface/ovpn-client/print detail
/interface/ovpn-client/monitor [find name="ovpn-to-vps"] once
/ip/address/print where interface=ovpn-to-vps
/log/print where topics~"ovpn"
```

**Expected results:**
- Status: `connected`
- Encoding: `AES-256-CBC/SHA1`
- IP address assigned on `ovpn-to-vps` interface

### Step 17: Test Remote Access

**From anywhere on the internet:**
- **Winbox:** Connect to `16.28.86.103:8291`
- **WebFig:** Open `http://16.28.86.103:8080`
- **SSH:** `ssh admin@16.28.86.103 -p 22022`

## Part 7: Adding Additional Routers

### Step 18: Add Second Router (Example)

```bash
# On VPS - create new client certificate
cd /etc/openvpn/easy-rsa
./easyrsa build-client-full mikrotik-client-04 nopass

# Prepare files
mkdir -p /root/mikrotik-client-04
cp /etc/openvpn/server/ca.crt /root/mikrotik-client-04/
cp pki/issued/mikrotik-client-04.crt /root/mikrotik-client-04/
cp pki/private/mikrotik-client-04.key /root/mikrotik-client-04/

# Set static IP (optional)
echo "ifconfig-push 10.8.0.5 255.255.255.0" > /etc/openvpn/server/ccd/mikrotik-client-04

# CRITICAL: Rebuild ALL router NAT rules (don't break existing ones)
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Router #1 rules (10.8.0.3)
iptables -t nat -A PREROUTING -p tcp --dport 8291 -j DNAT --to-destination 10.8.0.3:8291
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 8291 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.8.0.3:80
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 80 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 22022 -j DNAT --to-destination 10.8.0.3:22
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 22 -j SNAT --to-source 10.8.0.1

# Router #2 rules (10.8.0.5 - use different ports)
iptables -t nat -A PREROUTING -p tcp --dport 8295 -j DNAT --to-destination 10.8.0.5:8291
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.5 --dport 8291 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 8085 -j DNAT --to-destination 10.8.0.5:80
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.5 --dport 80 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 22030 -j DNAT --to-destination 10.8.0.5:22
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.5 --dport 22 -j SNAT --to-source 10.8.0.1

# Open new ports
ufw allow 8295/tcp
ufw allow 8085/tcp
ufw allow 22030/tcp

# Save rules
iptables-save > /etc/iptables/rules.v4

# Restart OpenVPN
systemctl restart openvpn-server@server
```

## Part 8: Troubleshooting Common Issues

### Issue: Service inactive but port listening
**Solution:** Stop conflicting services, use correct systemd unit

### Issue: Certificate import fails on MikroTik
**Solution:** Download files individually, verify file sizes

### Issue: TLS handshake fails
**Solution:** Use SHA1 auth, AES-256-CBC cipher, enable legacy provider

### Issue: Adding router breaks existing ones
**Solution:** Always rebuild ALL NAT rules, never use `iptables -F` alone

### Issue: RouterOS 7 syntax errors
**Solution:** Use forward slash syntax `/interface/ovpn-client/add`

## Summary

This guide provides the complete, tested procedure for setting up a VPS OpenVPN server for MikroTik remote management. Key success factors:

1. **TCP protocol** (not UDP) for MikroTik compatibility
2. **Correct cipher settings** (AES-256-CBC/SHA1)
3. **Proper file paths** for systemd service
4. **SNAT rules** for direct remote access
5. **RouterOS version awareness** (6 vs 7 syntax)
6. **Careful NAT rule management** for multiple routers

**Final Result:** Direct remote access to MikroTik routers via public VPS IP without requiring VPN client software.
