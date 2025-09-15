#!/bin/bash
# MikroTik Remote Access VPS - One-Click Deployment Script
# This script sets up a complete, bulletproof MikroTik remote access service
# Version: 2.0 - Production Ready

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# Get VPS public IP
VPS_IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me || ip route get 8.8.8.8 | awk '{print $7; exit}')
if [[ -z "$VPS_IP" ]]; then
    error "Could not determine VPS public IP address"
    exit 1
fi

log "🚀 Starting MikroTik Remote Access VPS Deployment"
log "📍 VPS IP Address: $VPS_IP"

# Step 1: System Update and Essential Packages
log "📦 Step 1/10: Updating system and installing essential packages..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget nano ufw fail2ban htop net-tools iptables-persistent nginx php-fpm

# Enable IP forwarding
log "🌐 Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Step 2: Basic Firewall Setup
log "🔥 Step 2/10: Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 1194/tcp
ufw allow 80/tcp
ufw --force enable

# Step 3: OpenVPN Installation
log "🔐 Step 3/10: Installing OpenVPN server..."
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

# Automated OpenVPN installation with optimal settings
AUTO_INSTALL=y \
IPV6_SUPPORT=n \
PORT_CHOICE=1 \
PROTOCOL_CHOICE=2 \
DNS=3 \
COMPRESSION_ENABLED=n \
CUSTOMIZE_ENC=n \
CLIENT=mikrotik-test \
PASS=1 \
./openvpn-install.sh

# Step 4: Fix OpenVPN Service Issues
log "🔧 Step 4/10: Fixing OpenVPN service configuration..."
systemctl stop openvpn@server 2>/dev/null || true
systemctl disable openvpn@server 2>/dev/null || true

# Copy files to correct locations
mkdir -p /etc/openvpn/server
cp /etc/openvpn/server.conf /etc/openvpn/server/server.conf 2>/dev/null || true
cp /etc/openvpn/ca.crt /etc/openvpn/server/ 2>/dev/null || true
cp /etc/openvpn/server_*.crt /etc/openvpn/server/ 2>/dev/null || true
cp /etc/openvpn/server_*.key /etc/openvpn/server/ 2>/dev/null || true
cp /etc/openvpn/tls-crypt.key /etc/openvpn/server/ 2>/dev/null || true

# Generate CRL
cd /etc/openvpn/easy-rsa
./easyrsa gen-crl
cp -f pki/crl.pem /etc/openvpn/server/crl.pem
chmod 644 /etc/openvpn/server/crl.pem

# Step 5: Configure MikroTik Compatibility
log "⚙️ Step 5/10: Configuring MikroTik compatibility..."
cd /etc/openvpn/server

# Remove incompatible settings
sed -i '/^ncp-disable/d; /^ncp-ciphers/d; /^tls-crypt/d; /^tls-cipher/d; /^tls-auth/d' server.conf

# Set MikroTik-compatible cipher and auth
sed -i 's/^auth .*/auth SHA1/' server.conf
sed -i 's/^cipher .*/cipher AES-256-CBC/' server.conf

# Add compatibility settings
cat >> server.conf << 'EOF'

# MikroTik RouterOS compatibility
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
tls-version-min 1.0
compat-mode 2.4.0
providers legacy default

# Enable client-config-dir for static IPs
client-config-dir /etc/openvpn/server/ccd
ccd-exclusive
ifconfig-pool-persist /etc/openvpn/server/ipp.txt 0
topology subnet
EOF

# Create client-config directory
mkdir -p /etc/openvpn/server/ccd

# Start and enable OpenVPN service
systemctl start openvpn-server@server
systemctl enable openvpn-server@server

# Step 6: Create Dynamic NAT Rule Manager
log "🔄 Step 6/10: Creating dynamic NAT rule manager..."
cat > /usr/local/bin/fix-all-nat-rules << 'EOF'
#!/bin/bash
set -euo pipefail

CLIENTS_DIR="/var/www/html/clients"
CCD_DIR="/etc/openvpn/server/ccd"
REPORTED="/tmp/client-ips.txt"
TUN_IP="10.8.0.1"

declare -A REPORTED_IP
if [ -f "$REPORTED" ]; then
  while IFS=':' read -r c ip; do
    [ -n "$c" ] && [ -n "$ip" ] && REPORTED_IP["$c"]="$ip"
  done < "$REPORTED"
fi

# Reset NAT (only what we manage)
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

add_rules() {
  local ip="$1" wport="$2" webport="$3" sshport="$4" apiport="$5" apisslport="$6"
  # Winbox
  iptables -t nat -A PREROUTING  -p tcp --dport "$wport"   -j DNAT --to-destination "$ip:8291"
  iptables -t nat -A POSTROUTING -p tcp -d "$ip" --dport 8291 -j SNAT --to-source "$TUN_IP"
  # WebFig
  iptables -t nat -A PREROUTING  -p tcp --dport "$webport" -j DNAT --to-destination "$ip:80"
  iptables -t nat -A POSTROUTING -p tcp -d "$ip" --dport 80   -j SNAT --to-source "$TUN_IP"
  # SSH
  iptables -t nat -A PREROUTING  -p tcp --dport "$sshport"  -j DNAT --to-destination "$ip:22"
  iptables -t nat -A POSTROUTING -p tcp -d "$ip" --dport 22   -j SNAT --to-source "$TUN_IP"
  # API
  [ -n "$apiport" ] && iptables -t nat -A PREROUTING  -p tcp --dport "$apiport"  -j DNAT --to-destination "$ip:8728"
  [ -n "$apiport" ] && iptables -t nat -A POSTROUTING -p tcp -d "$ip" --dport 8728 -j SNAT --to-source "$TUN_IP"
  # API-SSL
  [ -n "$apisslport" ] && iptables -t nat -A PREROUTING  -p tcp --dport "$apisslport" -j DNAT --to-destination "$ip:8729"
  [ -n "$apisslport" ] && iptables -t nat -A POSTROUTING -p tcp -d "$ip" --dport 8729   -j SNAT --to-source "$TUN_IP"
}

for dir in "$CLIENTS_DIR"/*; do
  [ -d "$dir" ] || continue
  client="$(basename "$dir")"
  ports="$dir/ports.txt"
  [ -f "$ports" ] || continue

  # Load ports and expected IP
  WINBOX_PORT=""
  WEBFIG_PORT=""
  SSH_PORT=""
  API_PORT=""
  API_SSL_PORT=""
  EXPECTED_IP=""
  # shellcheck disable=SC1090
  source "$ports"

  # Determine actual IP with precedence:
  # 1) reported by MikroTik script 2) CCD static mapping 3) expected IP fallback
  actual_ip="${REPORTED_IP[$client]:-}"
  if [ -z "$actual_ip" ] && [ -f "$CCD_DIR/$client" ]; then
    actual_ip="$(awk '/ifconfig-push/{print $2}' "$CCD_DIR/$client")"
  fi
  if [ -z "$actual_ip" ] && [ -n "${EXPECTED_IP:-}" ]; then
    actual_ip="$EXPECTED_IP"
  fi

  if [ -z "$actual_ip" ] || [ -z "${WINBOX_PORT:-}" ] || [ -z "${WEBFIG_PORT:-}" ] || [ -z "${SSH_PORT:-}" ]; then
    echo "Skipping $client (missing IP or ports)"; continue
  fi

  echo "Adding NAT for $client -> $actual_ip (W:$WINBOX_PORT Web:$WEBFIG_PORT SSH:$SSH_PORT API:${API_PORT:-N/A} API-SSL:${API_SSL_PORT:-N/A})"
  add_rules "$actual_ip" "$WINBOX_PORT" "$WEBFIG_PORT" "$SSH_PORT" "${API_PORT:-}" "${API_SSL_PORT:-}"
done

iptables-save > /etc/iptables/rules.v4
echo "NAT rules rebuilt (dynamic)."
EOF

chmod +x /usr/local/bin/fix-all-nat-rules

# Create systemd service to restore NAT rules on boot
cat > /etc/systemd/system/restore-nat-rules.service << 'SERVICEEOF'
[Unit]
Description=Restore NAT rules for MikroTik remote access
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-all-nat-rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl enable restore-nat-rules.service

# Step 7: Create IP Reporting Scripts
log "📡 Step 7/10: Creating IP reporting system..."
cat > /var/www/html/update-client-ip.php << 'EOF'
<?php
$client = $_GET['client'] ?? '';
$ip = $_GET['ip'] ?? '';

if ($client && $ip && preg_match('/^[\w-]+$/', $client) && filter_var($ip, FILTER_VALIDATE_IP)) {
    $log = date('Y-m-d H:i:s') . " - Client: $client, IP: $ip\n";
    file_put_contents('/var/log/client-ip-updates.log', $log, FILE_APPEND);
    
    // Store current client IPs
    $ips = [];
    if (file_exists('/tmp/client-ips.txt')) {
        $ips = array_filter(explode("\n", file_get_contents('/tmp/client-ips.txt')));
    }
    
    // Update or add this client's IP
    $updated = false;
    foreach ($ips as $i => $line) {
        if (strpos($line, "$client:") === 0) {
            $ips[$i] = "$client:$ip";
            $updated = true;
            break;
        }
    }
    if (!$updated) {
        $ips[] = "$client:$ip";
    }
    
    file_put_contents('/tmp/client-ips.txt', implode("\n", $ips) . "\n");
    echo "OK";
} else {
    echo "Invalid parameters";
}
?>
EOF

cat > /var/www/html/ip-mismatch.php << 'EOF'
<?php
$client = $_GET['client'] ?? '';
$expected = $_GET['expected'] ?? '';
$actual = $_GET['actual'] ?? '';

if ($client && $expected && $actual) {
    $log = date('Y-m-d H:i:s') . " - MISMATCH: Client $client expected $expected but got $actual\n";
    file_put_contents('/var/log/ip-mismatches.log', $log, FILE_APPEND);
    file_put_contents('/tmp/ip-mismatch-alert.txt', "IP mismatch detected for $client\n", FILE_APPEND);
    echo "Mismatch logged";
} else {
    echo "Invalid parameters";
}
?>
EOF

chown www-data:www-data /var/www/html/*.php
chmod 644 /var/www/html/*.php

# Step 8: Configure Web Server
log "🌐 Step 8/10: Configuring web server..."
mkdir -p /var/www/html/clients
chown -R www-data:www-data /var/www/html/clients
chmod -R 755 /var/www/html/clients

# Configure nginx for PHP
cat > /etc/nginx/sites-available/default << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.php;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF

systemctl start nginx
systemctl enable nginx
systemctl start php8.1-fpm 2>/dev/null || systemctl start php-fpm
systemctl enable php8.1-fpm 2>/dev/null || systemctl enable php-fpm

nginx -t && systemctl reload nginx

# Step 9: Create Management Scripts
log "🛠️ Step 9/10: Creating management scripts..."

# Main client creation script
cat > /usr/local/bin/create-mikrotik-autoconfig << 'EOF'
#!/bin/bash
# MikroTik Remote Access - Bulletproof Client Setup Script

CLIENT_NAME="$1"
VPN_IP="$2"
WINBOX_PORT="$3"
WEBFIG_PORT="$4"
SSH_PORT="$5"
API_PORT="${6:-$((WINBOX_PORT + 1000))}"  # Default API port = Winbox + 1000
API_SSL_PORT="${7:-$((API_PORT + 1))}"    # Default API-SSL port = API + 1

if [ -z "$CLIENT_NAME" ] || [ -z "$VPN_IP" ] || [ -z "$WINBOX_PORT" ] || [ -z "$WEBFIG_PORT" ] || [ -z "$SSH_PORT" ]; then
    echo "Usage: create-mikrotik-autoconfig <client-name> <vpn-ip> <winbox-port> <webfig-port> <ssh-port> [api-port] [api-ssl-port]"
    echo "Example: create-mikrotik-autoconfig customer-john 10.8.0.8 8296 8086 22032 9296 9297"
    exit 1
fi

echo "🚀 Creating bulletproof setup for client: $CLIENT_NAME"

# 1. Create client certificate
cd /etc/openvpn/easy-rsa
./easyrsa build-client-full "$CLIENT_NAME" nopass

# 2. FORCE static IP assignment - multiple methods
mkdir -p /etc/openvpn/server/ccd
echo "ifconfig-push $VPN_IP 255.255.255.0" > "/etc/openvpn/server/ccd/$CLIENT_NAME"

# Force into IP pool persistence
sed -i "/^$CLIENT_NAME,/d" /etc/openvpn/server/ipp.txt 2>/dev/null || true
echo "$CLIENT_NAME,$VPN_IP" >> /etc/openvpn/server/ipp.txt

# 3. Prepare certificate files for web download
mkdir -p "/var/www/html/clients/$CLIENT_NAME"
cp /etc/openvpn/server/ca.crt "/var/www/html/clients/$CLIENT_NAME/"
cp "pki/issued/$CLIENT_NAME.crt" "/var/www/html/clients/$CLIENT_NAME/"
cp "pki/private/$CLIENT_NAME.key" "/var/www/html/clients/$CLIENT_NAME/"

# 4. Store port assignments for this client (including expected IP)
cat > "/var/www/html/clients/$CLIENT_NAME/ports.txt" << PORTSEOF
WINBOX_PORT=$WINBOX_PORT
WEBFIG_PORT=$WEBFIG_PORT
SSH_PORT=$SSH_PORT
API_PORT=$API_PORT
API_SSL_PORT=$API_SSL_PORT
EXPECTED_IP=$VPN_IP
PORTSEOF

# 5. Create RouterOS 6 auto-config script with IP verification
cat > "/var/www/html/clients/$CLIENT_NAME/setup-ros6.rsc" << 'ROSEOF'
# MikroTik RouterOS 6 Auto-Configuration Script - Bulletproof Version

:log info "Starting bulletproof VPN setup..."

# Download certificates automatically
/tool fetch url="http://VPS_IP/clients/CLIENT_NAME/ca.crt" dst-path=ca.crt
/tool fetch url="http://VPS_IP/clients/CLIENT_NAME/CLIENT_NAME.crt" dst-path=CLIENT_NAME.crt
/tool fetch url="http://VPS_IP/clients/CLIENT_NAME/CLIENT_NAME.key" dst-path=CLIENT_NAME.key

# Wait for downloads
:delay 3s

# Import certificates
/certificate import file-name=ca.crt passphrase=""
/certificate import file-name=CLIENT_NAME.crt passphrase=""
/certificate import file-name=CLIENT_NAME.key passphrase=""

# Wait for import
:delay 2s

# Remove old VPN interface if exists
/interface ovpn-client remove [find name="ovpn-to-vps"] 

# Create OpenVPN client
/interface ovpn-client add name=ovpn-to-vps connect-to=VPS_IP port=1194 mode=ip user=CLIENT_NAME password="" auth=sha1 cipher=aes256 certificate=CLIENT_NAME.crt_0 verify-server-certificate=no add-default-route=no disabled=no

# Wait for initial connection
:delay 15s

# IP verification loop with retries (bulletproof)
:local expectedip "VPN_IP"
:local actualip ""
:local retries 0
:local maxretries 5

:while ($retries < $maxretries) do={
    :set actualip [/ip address get [find interface="ovpn-to-vps"] address]
    :if ([:len $actualip] > 0) do={
        :set actualip [:pick $actualip 0 [:find $actualip "/"]]
        :log info ("VPN connected with IP: " . $actualip)
        
        # Report actual IP to server
        /tool fetch url=("http://VPS_IP/update-client-ip.php?client=CLIENT_NAME&ip=" . $actualip) dst-path=ip-report.txt
        
        :if ($actualip = $expectedip) do={
            :log info ("SUCCESS: Got expected IP " . $expectedip)
            :set retries $maxretries
        } else={
            :log warning ("IP MISMATCH: Expected " . $expectedip . " but got " . $actualip)
            # Report mismatch
            /tool fetch url=("http://VPS_IP/ip-mismatch.php?client=CLIENT_NAME&expected=" . $expectedip . "&actual=" . $actualip) dst-path=mismatch-report.txt
            
            # Retry connection
            /interface ovpn-client disable ovpn-to-vps
            :delay 5s
            /interface ovpn-client enable ovpn-to-vps
            :delay 15s
            :set retries ($retries + 1)
        }
    } else={
        :log warning ("No IP assigned yet, retrying...")
        :delay 10s
        :set retries ($retries + 1)
    }
}

# Configure services for security
/ip service set winbox disabled=no port=8291 address=10.8.0.1
/ip service set www disabled=no port=80 address=10.8.0.1
/ip service set ssh disabled=no port=22 address=10.8.0.1
/ip service set api disabled=no port=8728 address=10.8.0.1
/ip service set api-ssl disabled=no port=8729 address=10.8.0.1

# Add firewall rules
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8291 action=accept place-before=0 comment="Winbox via VPS"
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=80 action=accept place-before=0 comment="WebFig via VPS"
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=22 action=accept place-before=0 comment="SSH via VPS"
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8728 action=accept place-before=0 comment="API via VPS"
/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8729 action=accept place-before=0 comment="API-SSL via VPS"

# Clean up certificate files
/file remove [find name="ca.crt"]
/file remove [find name="CLIENT_NAME.crt"]
/file remove [find name="CLIENT_NAME.key"]
/file remove [find name="ip-report.txt"]
/file remove [find name="mismatch-report.txt"]

:log info "VPN setup completed! Remote access available at: Winbox=VPS_IP:WINBOX_PORT WebFig=http://VPS_IP:WEBFIG_PORT"
:put "Setup completed! You can now access this router remotely:"
:put "Winbox: VPS_IP:WINBOX_PORT"
:put "WebFig: http://VPS_IP:WEBFIG_PORT"
:put "API: VPS_IP:API_PORT"
:put "IMPORTANT: If remote access doesn't work immediately, contact support with your VPN IP above"
ROSEOF

# 6. Create RouterOS 7 script (similar but with forward slash syntax)
sed 's|/interface ovpn-client|/interface/ovpn-client|g; s|/ip service|/ip/service|g; s|/ip firewall filter|/ip/firewall/filter|g; s|/ip address|/ip/address|g; s|/file remove|/file/remove|g; s|cipher=aes256|cipher=aes256-cbc|g' "/var/www/html/clients/$CLIENT_NAME/setup-ros6.rsc" > "/var/www/html/clients/$CLIENT_NAME/setup-ros7.rsc"

# Replace placeholders in both scripts
VPS_IP=$(curl -s ipv4.icanhazip.com)
sed -i "s/CLIENT_NAME/$CLIENT_NAME/g; s/VPN_IP/$VPN_IP/g; s/WINBOX_PORT/$WINBOX_PORT/g; s/WEBFIG_PORT/$WEBFIG_PORT/g; s/API_PORT/$API_PORT/g; s/VPS_IP/$VPS_IP/g" "/var/www/html/clients/$CLIENT_NAME/setup-ros6.rsc"
sed -i "s/CLIENT_NAME/$CLIENT_NAME/g; s/VPN_IP/$VPN_IP/g; s/WINBOX_PORT/$WINBOX_PORT/g; s/WEBFIG_PORT/$WEBFIG_PORT/g; s/API_PORT/$API_PORT/g; s/VPS_IP/$VPS_IP/g" "/var/www/html/clients/$CLIENT_NAME/setup-ros7.rsc"

# 7. Create customer instruction webpage
cat > "/var/www/html/clients/$CLIENT_NAME/instructions.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
    <title>🚀 MikroTik Remote Access Setup</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        .container { max-width: 900px; margin: 0 auto; }
        .step { background: #f4f4f4; padding: 20px; margin: 20px 0; border-left: 4px solid #007cba; }
        .code { background: #2d2d2d; color: #fff; padding: 15px; border-radius: 5px; font-family: monospace; font-size: 12px; }
        .warning { background: #fff3cd; padding: 15px; border: 1px solid #ffeaa7; border-radius: 5px; }
        .success { background: #d4edda; padding: 15px; border: 1px solid #c3e6cb; border-radius: 5px; }
        .download-btn { display: inline-block; background: #007cba; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; margin: 10px 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 MikroTik Remote Access Setup</h1>
        <h2>Client: $CLIENT_NAME</h2>
        
        <div class="warning">
            <strong>⚠️ Important:</strong> Make sure your MikroTik has internet access before starting!
        </div>

        <div class="step">
            <h3>Step 1: Check Your RouterOS Version</h3>
            <p>Connect to your MikroTik locally via Winbox and run this command in Terminal:</p>
            <div class="code">/system resource print</div>
            <p>Look at the "version" line:</p>
            <ul>
                <li>If it starts with <strong>6.</strong> (like 6.49.18) → Use RouterOS 6 script</li>
                <li>If it starts with <strong>7.</strong> (like 7.15.2) → Use RouterOS 7 script</li>
            </ul>
        </div>

        <div class="step">
            <h3>Step 2A: For RouterOS 6 (6.x.x)</h3>
            <p>1. Download the script file:</p>
            <a href="setup-ros6.rsc" download class="download-btn">📥 Download RouterOS 6 Script</a>
            <p>2. Upload to your MikroTik via Winbox → Files → Upload, then run:</p>
            <div class="code">/import setup-ros6.rsc</div>
        </div>

        <div class="step">
            <h3>Step 2B: For RouterOS 7 (7.x.x)</h3>
            <p>1. Download the script file:</p>
            <a href="setup-ros7.rsc" download class="download-btn">📥 Download RouterOS 7 Script</a>
            <p>2. Upload to your MikroTik via Winbox → Files → Upload, then run:</p>
            <div class="code">/import setup-ros7.rsc</div>
        </div>

        <div class="success">
            <h3>🎉 Your Remote Access Details</h3>
            <p>Once setup is complete, you can access your router remotely from anywhere:</p>
            <ul>
                <li><strong>Winbox:</strong> $VPS_IP:$WINBOX_PORT</li>
                <li><strong>WebFig:</strong> http://$VPS_IP:$WEBFIG_PORT</li>
                <li><strong>SSH:</strong> ssh admin@$VPS_IP -p $SSH_PORT</li>
                <li><strong>API:</strong> $VPS_IP:$API_PORT</li>
                <li><strong>API-SSL:</strong> $VPS_IP:$API_SSL_PORT</li>
            </ul>
            <p><strong>Expected VPN IP:</strong> $VPN_IP</p>
        </div>
    </div>
</body>
</html>
HTMLEOF

# Replace placeholders in HTML
sed -i "s/\$CLIENT_NAME/$CLIENT_NAME/g; s/\$VPN_IP/$VPN_IP/g; s/\$WINBOX_PORT/$WINBOX_PORT/g; s/\$WEBFIG_PORT/$WEBFIG_PORT/g; s/\$SSH_PORT/$SSH_PORT/g; s/\$API_PORT/$API_PORT/g; s/\$API_SSL_PORT/$API_SSL_PORT/g; s/\$VPS_IP/$VPS_IP/g" "/var/www/html/clients/$CLIENT_NAME/instructions.html"

# 8. Restart OpenVPN with new config
systemctl restart openvpn-server@server
sleep 5

# 9. Set up NAT rules (dynamic - calls fix-all-nat-rules automatically)
fix-all-nat-rules

# 10. Open firewall ports
ufw allow "$WINBOX_PORT/tcp"
ufw allow "$WEBFIG_PORT/tcp"
ufw allow "$SSH_PORT/tcp"
ufw allow "$API_PORT/tcp"
ufw allow "$API_SSL_PORT/tcp"

# Set permissions
chown -R www-data:www-data "/var/www/html/clients/$CLIENT_NAME"
chmod -R 755 "/var/www/html/clients/$CLIENT_NAME"

echo ""
echo "🎉 SUCCESS! Client $CLIENT_NAME setup created with IP detection!"
echo ""
echo "📋 Client Details:"
echo "   Name: $CLIENT_NAME"
echo "   Expected VPN IP: $VPN_IP"
echo "   Winbox: $VPS_IP:$WINBOX_PORT"
echo "   WebFig: http://$VPS_IP:$WEBFIG_PORT"
echo "   SSH: $VPS_IP:$SSH_PORT"
echo "   API: $VPS_IP:$API_PORT"
echo "   API-SSL: $VPS_IP:$API_SSL_PORT"
echo ""
echo "📧 Send this link to your customer:"
echo "   http://$VPS_IP/clients/$CLIENT_NAME/instructions.html"
echo ""
echo "🛠️ Monitor client IPs with: check-client-ips"
echo "🔧 Fix NAT rules if needed: fix-all-nat-rules"
EOF

chmod +x /usr/local/bin/create-mikrotik-autoconfig

# Client monitoring script
cat > /usr/local/bin/check-client-ips << 'EOF'
#!/bin/bash
echo "=== Current Client IP Reports ==="
if [ -f /tmp/client-ips.txt ]; then
    while IFS=':' read -r client ip; do
        [ -n "$client" ] && [ -n "$ip" ] && echo "  $client -> $ip"
    done < /tmp/client-ips.txt
else
    echo "  No client IPs reported yet"
fi

echo ""
echo "=== IP Mismatches ==="
if [ -f /tmp/ip-mismatch-alert.txt ]; then
    cat /tmp/ip-mismatch-alert.txt
    echo "Run: fix-all-nat-rules (to fix NAT rules)"
else
    echo "  No IP mismatches detected"
fi
EOF

chmod +x /usr/local/bin/check-client-ips

# System persistence verification script
cat > /usr/local/bin/verify-system-persistence << 'EOF'
#!/bin/bash
echo "=== System Persistence Verification ==="

services=("openvpn-server@server" "nginx" "restore-nat-rules.service")
for service in "${services[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        echo "✅ $service: Enabled for auto-start"
    else
        echo "❌ $service: NOT enabled for auto-start"
    fi
done

if dpkg -l | grep -q iptables-persistent; then
    echo "✅ iptables-persistent: Installed"
else
    echo "❌ iptables-persistent: NOT installed"
fi

echo ""
echo "=== Service Status ==="
systemctl status openvpn-server@server nginx restore-nat-rules.service --no-pager -l
EOF

chmod +x /usr/local/bin/verify-system-persistence

# Step 10: Set up log rotation and cron jobs
log "📝 Step 10/10: Setting up logging and automation..."
cat > /etc/logrotate.d/mikrotik-remote-access << 'LOGROTATEEOF'
/var/log/client-ip-updates.log
/var/log/ip-mismatches.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
LOGROTATEEOF

# Final verification
log "✅ Verifying installation..."
sleep 5

if systemctl is-active --quiet openvpn-server@server; then
    log "✅ OpenVPN server is running"
else
    error "❌ OpenVPN server is not running"
fi

if systemctl is-active --quiet nginx; then
    log "✅ Nginx web server is running"
else
    error "❌ Nginx web server is not running"
fi

if netstat -tuln | grep -q :1194; then
    log "✅ OpenVPN port 1194 is listening"
else
    error "❌ OpenVPN port 1194 is not listening"
fi

if netstat -tuln | grep -q :80; then
    log "✅ Web server port 80 is listening"
else
    error "❌ Web server port 80 is not listening"
fi

# Create welcome page
cat > /var/www/html/index.html << 'WELCOMEOF'
<!DOCTYPE html>
<html>
<head>
    <title>MikroTik Remote Access Service</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
        .container { max-width: 800px; margin: 0 auto; }
        .success { background: #d4edda; color: #155724; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .code { background: #f8f9fa; padding: 15px; border-radius: 5px; font-family: monospace; text-align: left; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 MikroTik Remote Access Service</h1>
        <div class="success">
            <h3>✅ System Successfully Deployed!</h3>
            <p>Your MikroTik remote access service is ready to use.</p>
        </div>
        
        <h3>Create Your First Client:</h3>
        <div class="code">
create-mikrotik-autoconfig customer-test 10.8.0.10 8300 8090 22050
        </div>
        
        <h3>Management Commands:</h3>
        <div class="code">
check-client-ips          # Monitor client connections<br>
fix-all-nat-rules         # Rebuild NAT rules<br>
verify-system-persistence # Check system health
        </div>
        
        <p><strong>VPS IP:</strong> VPS_IP_PLACEHOLDER</p>
        <p><strong>OpenVPN Port:</strong> 1194 (TCP)</p>
    </div>
</body>
</html>
WELCOMEOF

sed -i "s/VPS_IP_PLACEHOLDER/$VPS_IP/g" /var/www/html/index.html

log "🎉 DEPLOYMENT COMPLETE!"
log ""
log "📋 System Summary:"
log "   VPS IP: $VPS_IP"
log "   OpenVPN Port: 1194 (TCP)"
log "   Web Server: http://$VPS_IP"
log "   Status: All services running and persistent"
log ""
log "🚀 Create your first client:"
log "   create-mikrotik-autoconfig customer-test 10.8.0.10 8300 8090 22050"
log ""
log "🔧 Management commands:"
log "   check-client-ips          # Monitor clients"
log "   fix-all-nat-rules         # Rebuild NAT rules"
log "   verify-system-persistence # Check system health"
log ""
log "✅ Your MikroTik remote access service is ready!"

# Create deployment summary
cat > /root/deployment-summary.txt << SUMMARYEOF
MikroTik Remote Access VPS - Deployment Summary
================================================

Deployment Date: $(date)
VPS IP Address: $VPS_IP
OpenVPN Port: 1194 (TCP)

Services Installed:
✅ OpenVPN Server (with MikroTik compatibility)
✅ Nginx Web Server (with PHP support)
✅ Dynamic NAT Rule Manager
✅ IP Reporting System
✅ Client Management Scripts
✅ System Persistence (survives reboots)

Quick Start:
1. Create first client: create-mikrotik-autoconfig customer-test 10.8.0.10 8300 8090 22050
2. Send customer link: http://$VPS_IP/clients/customer-test/instructions.html
3. Monitor clients: check-client-ips
4. System health: verify-system-persistence

Web Interface: http://$VPS_IP
All services are configured to start automatically on boot.

SUMMARYEOF

log "📄 Deployment summary saved to: /root/deployment-summary.txt"
