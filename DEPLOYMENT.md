# 🚀 MikroTik Remote Access - One-Click VPS Deployment

## Quick Start (5 Minutes)

Deploy a complete, bulletproof MikroTik remote access service on any Ubuntu VPS:

### Step 1: Download and Deploy
```bash
# Connect to your fresh Ubuntu VPS as root
ssh root@YOUR_VPS_IP

# Download and run the deployment script
curl -O https://raw.githubusercontent.com/your-repo/mikrotik-remote-access/main/vps-one-click-deploy.sh
chmod +x vps-one-click-deploy.sh
./vps-one-click-deploy.sh
```

### Step 2: Create First Client
```bash
# After deployment completes, create your first client
create-mikrotik-autoconfig customer-test 10.8.0.10 8300 8090 22050
```

### Step 3: Customer Setup
Send your customer this link (output from step 2):
```
http://YOUR_VPS_IP/clients/customer-test/instructions.html
```

Customer process:
1. Opens the webpage
2. Downloads RouterOS script for their version
3. Uploads to MikroTik via Winbox → Files
4. Runs: `/import setup-ros6.rsc` (or setup-ros7.rsc)
5. Gets immediate remote access

## What You Get

### ✅ Complete Service Features
- **OpenVPN Server** with MikroTik compatibility (TCP, AES-256-CBC, SHA1)
- **Dynamic NAT Rules** - supports unlimited clients (no hardcoded IPs)
- **Bulletproof IP Assignment** - multiple enforcement methods with auto-retry
- **API Support** - Legacy API (8728) and API-SSL (8729) forwarding
- **Web Management** - Professional customer onboarding system
- **Real-time Monitoring** - IP reporting and mismatch detection
- **Complete Persistence** - survives server reboots automatically

### 🎯 Customer Experience
- **Zero technical skills required** - just download and import script
- **30-60 second setup** - fully automated configuration
- **Professional webpage** with clear instructions
- **Multiple access methods** - Winbox, WebFig, SSH, API
- **Immediate remote access** - no VPN client software needed

### 🛠️ Admin Benefits
- **One command client creation** - fully automated
- **Unlimited scalability** - no hardcoded limits
- **Real-time monitoring** - `check-client-ips`
- **Automatic problem resolution** - system fixes IP mismatches
- **Zero maintenance** - all services auto-restart on boot

## Management Commands

After deployment, use these commands:

```bash
# Create new clients
create-mikrotik-autoconfig <client-name> <vpn-ip> <winbox-port> <webfig-port> <ssh-port>

# Monitor client connections
check-client-ips

# Rebuild NAT rules (if needed)
fix-all-nat-rules

# Check system health
verify-system-persistence

# View deployment summary
cat /root/deployment-summary.txt
```

## Example Client Creation

```bash
# Business client with custom ports
create-mikrotik-autoconfig acme-corp 10.8.0.25 8305 8095 22045

# Home office client
create-mikrotik-autoconfig john-home 10.8.0.26 8306 8096 22046

# Branch office with API access
create-mikrotik-autoconfig branch-nyc 10.8.0.27 8307 8097 22047 9307 9308
```

Each client gets:
- **Unique certificates** and static VPN IP
- **Dedicated public ports** for all services
- **Professional instruction webpage**
- **RouterOS 6 & 7 compatible scripts**
- **Automatic IP verification and retry**

## Deployment Script Features

The `vps-one-click-deploy.sh` includes:

### 🔧 System Setup
- Ubuntu package updates and essential tools
- IP forwarding and firewall configuration
- Service persistence (auto-start on boot)

### 🔐 OpenVPN Configuration
- Automated installation with MikroTik-optimized settings
- Certificate authority and client management
- Compatibility with RouterOS 6.49.10+ and RouterOS 7.x
- Service conflict resolution and path fixes

### 🌐 Web Server
- Nginx with PHP support
- Client file hosting and management
- IP reporting system (PHP scripts)
- Professional customer onboarding pages

### ⚙️ Management System
- Dynamic NAT rule manager (no hardcoded IPs)
- Client creation and monitoring scripts
- IP verification and mismatch detection
- System health monitoring tools

### 📊 Monitoring & Logging
- Real-time client IP reporting
- Automatic log rotation
- Health verification scripts
- Deployment summary and documentation

## Requirements

- **VPS**: Ubuntu 20.04+ or 22.04+ (fresh installation recommended)
- **Access**: Root SSH access
- **Network**: Public IP address
- **Resources**: 1GB RAM, 10GB disk (minimal requirements)

## Support

After deployment, your system includes:
- Complete documentation in `/root/deployment-summary.txt`
- Health check with `verify-system-persistence`
- Client monitoring with `check-client-ips`
- All services configured for automatic restart

The deployment script creates a bulletproof, production-ready MikroTik remote access service that scales to unlimited clients with zero maintenance required.

## Files Created

The deployment creates these key files:
- `/usr/local/bin/create-mikrotik-autoconfig` - Main client creation script
- `/usr/local/bin/fix-all-nat-rules` - Dynamic NAT rule manager
- `/usr/local/bin/check-client-ips` - Client monitoring
- `/usr/local/bin/verify-system-persistence` - Health checker
- `/var/www/html/clients/` - Client management directory
- `/etc/systemd/system/restore-nat-rules.service` - Boot persistence
- `/root/deployment-summary.txt` - Complete system documentation

Transform your VPS into a professional MikroTik remote access service in under 5 minutes! 🎉
