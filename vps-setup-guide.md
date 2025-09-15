# VPS Setup Guide for MikroTik Remote Access Service

## VPS Information
- **IP Address:** 16.28.86.103
- **Purpose:** OpenVPN Server for MikroTik remote management
- **Target OS:** Ubuntu 20.04/22.04 LTS (recommended)

## Prerequisites
- Root access to VPS
- SSH client
- Domain name (optional but recommended)

## Step-by-Step Setup

### 1. Initial VPS Setup

```bash
# Connect to VPS
ssh root@16.28.86.103

# Update system
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget nano ufw fail2ban htop

# Set up firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 1194/tcp  # OpenVPN port
ufw allow 443/tcp   # Alternative OpenVPN port (stealth)
ufw allow 80/tcp    # HTTP (for web interface)
ufw allow 443/udp   # HTTPS (for web interface)
ufw --force enable
```

### 2. OpenVPN Server Installation

```bash
# Download and run OpenVPN installation script
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

# Run the installer (interactive)
./openvpn-install.sh
```

**Installation Options:**
- IP address: 16.28.86.103
- Protocol: TCP (required for MikroTik)
- Port: 1194 (or 443 for stealth)
- DNS: 1.1.1.1, 1.0.0.1 (Cloudflare)
- Compression: No (better security)
- Customized encryption: No (use defaults)

### 3. OpenVPN Server Configuration

```bash
# Edit server configuration
nano /etc/openvpn/server/server.conf
```

**Key configurations for MikroTik compatibility:**

```conf
# Protocol (MikroTik only supports TCP)
proto tcp
port 1194

# Network configuration
server 10.8.0.0 255.255.255.0
topology subnet

# Push routes to clients
push "route 192.168.1.0 255.255.255.0"  # Adjust to your network
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Client-to-client communication
client-to-client

# Keep alive
keepalive 10 120

# Compression (disable for better security)
compress

# Security
cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256

# User/Group
user nobody
group nogroup

# Persistence
persist-key
persist-tun

# Logging
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 3
```

### 4. Certificate Management Setup

```bash
# Navigate to Easy-RSA directory
cd /etc/openvpn/server/easy-rsa/

# Generate client certificate (example for first client)
./easyrsa build-client-full mikrotik-client-01 nopass

# Create client configuration directory
mkdir -p /etc/openvpn/clients
```

### 5. Client Configuration Generator Script

```bash
# Create client config generator script
nano /etc/openvpn/make_config.sh
```

```bash
#!/bin/bash

# Client configuration generator for MikroTik
CLIENT_NAME=$1
SERVER_IP="16.28.86.103"
SERVER_PORT="1194"

if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: $0 <client_name>"
    exit 1
fi

# Generate client certificate
cd /etc/openvpn/server/easy-rsa/
./easyrsa build-client-full $CLIENT_NAME nopass

# Create client config
cat > /etc/openvpn/clients/${CLIENT_NAME}.ovpn << EOF
client
dev tun
proto tcp
remote $SERVER_IP $SERVER_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3

<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/server/easy-rsa/pki/issued/${CLIENT_NAME}.crt)
</cert>

<key>
$(cat /etc/openvpn/server/easy-rsa/pki/private/${CLIENT_NAME}.key)
</key>

<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
key-direction 1
EOF

echo "Client configuration created: /etc/openvpn/clients/${CLIENT_NAME}.ovpn"
```

```bash
# Make script executable
chmod +x /etc/openvpn/make_config.sh
```

### 6. Web Interface Setup (Optional)

```bash
# Install web server
apt install -y nginx php-fpm php-mysql mysql-server

# Create web directory
mkdir -p /var/www/mikrotik-manager
chown -R www-data:www-data /var/www/mikrotik-manager
```

### 7. Monitoring and Logging

```bash
# Create log directory
mkdir -p /var/log/openvpn
chown openvpn:openvpn /var/log/openvpn

# Set up log rotation
cat > /etc/logrotate.d/openvpn << EOF
/var/log/openvpn/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 openvpn openvpn
    postrotate
        systemctl reload openvpn-server@server
    endscript
}
EOF
```

### 8. Service Management

```bash
# Enable and start OpenVPN
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

# Check status
systemctl status openvpn-server@server

# View logs
journalctl -u openvpn-server@server -f
```

### 9. Testing the Setup

```bash
# Generate test client
/etc/openvpn/make_config.sh test-client

# Check if client config was created
ls -la /etc/openvpn/clients/

# Monitor connections
tail -f /var/log/openvpn/openvpn.log
```

### 10. Security Hardening

```bash
# Install and configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Configure SSH key authentication (disable password auth)
nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
systemctl restart ssh

# Set up automatic updates
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

## MikroTik Router Configuration

Once the VPS is set up, configure your MikroTik router:

1. **Upload certificates to MikroTik:**
   - Download the client `.ovpn` file
   - Extract certificates and import to MikroTik

2. **Create OpenVPN client interface:**
   - Go to PPP → Interface → Add OVPN Client
   - Connect To: 16.28.86.103
   - Port: 1194
   - Mode: IP
   - Add certificates and authentication

3. **Configure routing and firewall:**
   - Add routes through VPN interface
   - Set up NAT rules if needed

## Maintenance

### Regular Tasks:
- Monitor connection logs
- Update system packages
- Rotate certificates before expiry
- Monitor disk space and performance
- Review firewall logs

### Client Management:
- Generate new client certificates as needed
- Revoke compromised certificates
- Monitor active connections

## Troubleshooting

### Common Issues:
1. **Connection timeouts:** Check firewall rules
2. **Certificate errors:** Verify certificate validity
3. **Routing issues:** Check server push routes
4. **Performance issues:** Monitor server resources

### Log Locations:
- OpenVPN: `/var/log/openvpn/openvpn.log`
- System: `/var/log/syslog`
- Authentication: `/var/log/auth.log`

## Next Steps

1. Test connection with a MikroTik device
2. Implement web-based management interface
3. Set up monitoring and alerting
4. Create automated backup procedures
5. Document client onboarding process
