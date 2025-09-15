#!/bin/bash

# MikroTik Remote Access VPS Setup Script
# For Ubuntu 20.04/22.04 LTS
# VPS IP: 45.93.94.98

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VPS_IP="45.93.94.98"
OPENVPN_PORT="1194"
OPENVPN_PROTOCOL="tcp"
OPENVPN_DNS1="1.1.1.1"
OPENVPN_DNS2="1.0.0.1"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Update system
update_system() {
    print_status "Updating system packages..."
    apt update && apt upgrade -y
    print_status "System updated successfully"
}

# Install essential packages
install_essentials() {
    print_status "Installing essential packages..."
    apt install -y curl wget nano ufw fail2ban htop net-tools iptables-persistent
    print_status "Essential packages installed"
}

# Configure firewall
setup_firewall() {
    print_status "Configuring UFW firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow essential services
    ufw allow ssh
    ufw allow ${OPENVPN_PORT}/${OPENVPN_PROTOCOL}
    ufw allow 443/tcp   # Alternative OpenVPN port
    ufw allow 80/tcp    # HTTP for web interface
    ufw allow 443/udp   # HTTPS for web interface
    
    # Enable firewall
    ufw --force enable
    
    print_status "Firewall configured successfully"
}

# Download and install OpenVPN
install_openvpn() {
    print_status "Downloading OpenVPN installation script..."
    
    # Download the installation script
    curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
    chmod +x openvpn-install.sh
    
    print_status "Running OpenVPN installation..."
    
    # Set environment variables for automated installation
    export AUTO_INSTALL=y
    export APPROVE_INSTALL=y
    export APPROVE_IP=${VPS_IP}
    export IPV6_SUPPORT=n
    export PORT_CHOICE=1
    export PROTOCOL_CHOICE=2  # TCP
    export DNS=3  # Custom DNS
    export DNS1=${OPENVPN_DNS1}
    export DNS2=${OPENVPN_DNS2}
    export COMPRESSION_ENABLED=n
    export CUSTOMIZE_ENC=n
    export CLIENT=mikrotik-client-01
    export PASS=1  # No password for client key
    
    # Run the installation script
    ./openvpn-install.sh
    
    print_status "OpenVPN installed successfully"
}

# Configure OpenVPN for MikroTik compatibility
configure_openvpn() {
    print_status "Configuring OpenVPN for MikroTik compatibility..."
    
    # Backup original configuration
    cp /etc/openvpn/server/server.conf /etc/openvpn/server/server.conf.backup
    
    # Update server configuration for MikroTik compatibility
    cat >> /etc/openvpn/server/server.conf << EOF

# MikroTik specific configurations
topology subnet
client-to-client
compress lz4-v2
push "compress lz4-v2"

# Enhanced security
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256

# Logging
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 3

# Client management
client-config-dir /etc/openvpn/server/ccd
EOF

    # Create client config directory
    mkdir -p /etc/openvpn/server/ccd
    mkdir -p /var/log/openvpn
    chown openvpn:openvpn /var/log/openvpn
    
    # Restart OpenVPN service
    systemctl restart openvpn-server@server
    
    print_status "OpenVPN configured for MikroTik compatibility"
}

# Create client management scripts
create_management_scripts() {
    print_status "Creating client management scripts..."
    
    # Create client configuration generator
    cat > /usr/local/bin/create-mikrotik-client << 'EOF'
#!/bin/bash

CLIENT_NAME=$1
SERVER_IP="45.93.94.98"
SERVER_PORT="1194"

if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: $0 <client_name>"
    exit 1
fi

# Check if client already exists
if [ -f "/etc/openvpn/server/easy-rsa/pki/issued/${CLIENT_NAME}.crt" ]; then
    echo "Client $CLIENT_NAME already exists!"
    exit 1
fi

# Generate client certificate
cd /etc/openvpn/server/easy-rsa/
./easyrsa build-client-full $CLIENT_NAME nopass

# Create client config directory if it doesn't exist
mkdir -p /etc/openvpn/clients

# Create client configuration for MikroTik
cat > /etc/openvpn/clients/${CLIENT_NAME}.ovpn << EOFCLIENT
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
compress lz4-v2
verb 3
key-direction 1

<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>

<cert>
$(openssl x509 -in /etc/openvpn/server/easy-rsa/pki/issued/${CLIENT_NAME}.crt)
</cert>

<key>
$(cat /etc/openvpn/server/easy-rsa/pki/private/${CLIENT_NAME}.key)
</key>

<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
EOFCLIENT

echo "Client configuration created: /etc/openvpn/clients/${CLIENT_NAME}.ovpn"
echo "Download this file and configure it on your MikroTik router"
EOF

    chmod +x /usr/local/bin/create-mikrotik-client
    
    # Create client revocation script
    cat > /usr/local/bin/revoke-mikrotik-client << 'EOF'
#!/bin/bash

CLIENT_NAME=$1

if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: $0 <client_name>"
    exit 1
fi

# Revoke client certificate
cd /etc/openvpn/server/easy-rsa/
./easyrsa revoke $CLIENT_NAME
./easyrsa gen-crl

# Update OpenVPN CRL
cp pki/crl.pem /etc/openvpn/server/crl.pem
chown openvpn:openvpn /etc/openvpn/server/crl.pem

# Remove client config
rm -f /etc/openvpn/clients/${CLIENT_NAME}.ovpn

# Restart OpenVPN
systemctl restart openvpn-server@server

echo "Client $CLIENT_NAME has been revoked and removed"
EOF

    chmod +x /usr/local/bin/revoke-mikrotik-client
    
    # Create status script
    cat > /usr/local/bin/openvpn-status << 'EOF'
#!/bin/bash

echo "=== OpenVPN Server Status ==="
systemctl status openvpn-server@server --no-pager

echo -e "\n=== Active Connections ==="
if [ -f /var/log/openvpn/openvpn-status.log ]; then
    cat /var/log/openvpn/openvpn-status.log
else
    echo "No status file found"
fi

echo -e "\n=== Recent Log Entries ==="
tail -n 20 /var/log/openvpn/openvpn.log 2>/dev/null || echo "No log file found"
EOF

    chmod +x /usr/local/bin/openvpn-status
    
    print_status "Management scripts created successfully"
}

# Setup log rotation
setup_logging() {
    print_status "Setting up log rotation..."
    
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
        systemctl reload openvpn-server@server > /dev/null 2>&1 || true
    endscript
}
EOF

    print_status "Log rotation configured"
}

# Configure fail2ban
setup_fail2ban() {
    print_status "Configuring fail2ban..."
    
    cat > /etc/fail2ban/jail.d/openvpn.conf << EOF
[openvpn]
enabled = true
port = ${OPENVPN_PORT}
protocol = ${OPENVPN_PROTOCOL}
filter = openvpn
logpath = /var/log/openvpn/openvpn.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    systemctl restart fail2ban
    print_status "Fail2ban configured for OpenVPN"
}

# Create monitoring script
create_monitoring() {
    print_status "Creating monitoring script..."
    
    cat > /usr/local/bin/monitor-openvpn << 'EOF'
#!/bin/bash

# Check if OpenVPN service is running
if ! systemctl is-active --quiet openvpn-server@server; then
    echo "$(date): OpenVPN service is not running, attempting to start..." >> /var/log/openvpn-monitor.log
    systemctl start openvpn-server@server
    
    # Send notification (you can customize this)
    # mail -s "OpenVPN Service Restarted" admin@yourdomain.com < /dev/null
fi

# Check if OpenVPN is listening on the correct port
if ! netstat -tuln | grep -q ":${OPENVPN_PORT}"; then
    echo "$(date): OpenVPN is not listening on port ${OPENVPN_PORT}" >> /var/log/openvpn-monitor.log
fi
EOF

    chmod +x /usr/local/bin/monitor-openvpn
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/monitor-openvpn") | crontab -
    
    print_status "Monitoring script created and scheduled"
}

# Enable IP forwarding
enable_ip_forwarding() {
    print_status "Enabling IP forwarding..."
    
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sysctl -p
    
    print_status "IP forwarding enabled"
}

# Create initial client
create_initial_client() {
    print_status "Creating initial client configuration..."
    
    /usr/local/bin/create-mikrotik-client mikrotik-demo
    
    print_status "Initial client 'mikrotik-demo' created"
    print_warning "Client configuration file: /etc/openvpn/clients/mikrotik-demo.ovpn"
}

# Main installation function
main() {
    print_status "Starting MikroTik Remote Access VPS Setup"
    print_status "VPS IP: ${VPS_IP}"
    print_status "OpenVPN Port: ${OPENVPN_PORT}/${OPENVPN_PROTOCOL}"
    
    check_root
    update_system
    install_essentials
    setup_firewall
    enable_ip_forwarding
    install_openvpn
    configure_openvpn
    create_management_scripts
    setup_logging
    setup_fail2ban
    create_monitoring
    create_initial_client
    
    print_status "Installation completed successfully!"
    echo ""
    print_status "=== Next Steps ==="
    print_status "1. Download client config: /etc/openvpn/clients/mikrotik-demo.ovpn"
    print_status "2. Configure your MikroTik router using the client setup guide"
    print_status "3. Test the connection"
    echo ""
    print_status "=== Useful Commands ==="
    print_status "Create new client: create-mikrotik-client <name>"
    print_status "Revoke client: revoke-mikrotik-client <name>"
    print_status "Check status: openvpn-status"
    print_status "View logs: tail -f /var/log/openvpn/openvpn.log"
    echo ""
    print_warning "Remember to secure your VPS with SSH keys and disable password authentication!"
}

# Run main function
main "$@"
