# Complete MikroTik Remote Access Service Guide

## Overview - What We've Built

You now have a working MikroTik remote access service that allows you to manage customer routers from anywhere in the world. Here's how it works:

```
[Your Computer] → [VPS: 16.28.86.103] → [Customer's MikroTik Router]
    (Winbox)         (OpenVPN Server)         (OpenVPN Client)
```

**Current Status:**
- ✅ VPS OpenVPN Server: Running on 16.28.86.103:1194
- ✅ Router #1: `mikrotik-test` (RouterOS 6.49.18) - VPN IP: 10.8.0.2
- ✅ Router #2: `mikrotik-client-02` (RouterOS 6.49.10) - VPN IP: 10.8.0.3
- ✅ Router #3: `mikrotik-client-04` (RouterOS 7.x) - VPN IP: 10.8.0.7

## Part 1: How to Connect to Existing Routers

### Router #2 (RouterOS 6.49.10)
- **Winbox:** Connect to `16.28.86.103:8291`
- **WebFig:** Open `http://16.28.86.103:8080`
- **SSH:** `ssh admin@16.28.86.103 -p 22022`

### Router #3 (RouterOS 7.x)
- **Winbox:** Connect to `16.28.86.103:8295`
- **WebFig:** Open `http://16.28.86.103:8085`
- **SSH:** `ssh admin@16.28.86.103 -p 22030`

These work because your VPS forwards:
- Router #2: Port 8291→8291, 8080→80, 22022→22 (VPN IP: 10.8.0.3)
- Router #3: Port 8295→8291, 8085→80, 22030→22 (VPN IP: 10.8.0.7)

## Part 2: Adding New MikroTik Routers (Step by Step)

### Step 1: Create Automation Script on VPS

**On your VPS, create the automation script:**

```bash
nano /usr/local/bin/add-mikrotik-client
```

**Paste this exact script:**

```bash
#!/bin/bash
# MikroTik Remote Access - Add New Client Script

CLIENT_NAME="$1"
VPN_IP="$2"
WINBOX_PORT="$3"
WEBFIG_PORT="$4"
SSH_PORT="$5"

if [ -z "$CLIENT_NAME" ] || [ -z "$VPN_IP" ] || [ -z "$WINBOX_PORT" ] || [ -z "$WEBFIG_PORT" ] || [ -z "$SSH_PORT" ]; then
    echo "Usage: add-mikrotik-client <client-name> <vpn-ip> <winbox-port> <webfig-port> <ssh-port>"
    echo "Example: add-mikrotik-client customer-abc 10.8.0.5 8293 8083 22026"
    exit 1
fi

echo "=== Adding MikroTik Client: $CLIENT_NAME ==="
echo "VPN IP: $VPN_IP"
echo "Public Ports: Winbox=$WINBOX_PORT, WebFig=$WEBFIG_PORT, SSH=$SSH_PORT"
echo ""

# Step 1: Create client certificate
echo "[1/6] Creating client certificate..."
cd /etc/openvpn/server/easy-rsa
./easyrsa build-client-full "$CLIENT_NAME" nopass

# Step 2: Set static VPN IP
echo "[2/6] Setting static VPN IP..."
mkdir -p /etc/openvpn/server/ccd
echo "ifconfig-push $VPN_IP 255.255.255.0" > "/etc/openvpn/server/ccd/$CLIENT_NAME"

# Step 3: Prepare client files
echo "[3/6] Preparing client files..."
mkdir -p "/root/$CLIENT_NAME"
cp /etc/openvpn/server/ca.crt "/root/$CLIENT_NAME/"
cp "/etc/openvpn/server/easy-rsa/pki/issued/$CLIENT_NAME.crt" "/root/$CLIENT_NAME/"
cp "/etc/openvpn/server/easy-rsa/pki/private/$CLIENT_NAME.key" "/root/$CLIENT_NAME/"

# Step 4: Restart OpenVPN server
echo "[4/6] Restarting OpenVPN server..."
systemctl restart openvpn-server@server

# Step 5: Add port forwarding rules
echo "[5/6] Adding port forwarding rules..."

# Winbox forwarding
iptables -t nat -A PREROUTING -p tcp --dport $WINBOX_PORT -j DNAT --to-destination $VPN_IP:8291
iptables -t nat -A POSTROUTING -p tcp -d $VPN_IP --dport 8291 -j SNAT --to-source 10.8.0.1

# WebFig forwarding
iptables -t nat -A PREROUTING -p tcp --dport $WEBFIG_PORT -j DNAT --to-destination $VPN_IP:80
iptables -t nat -A POSTROUTING -p tcp -d $VPN_IP --dport 80 -j SNAT --to-source 10.8.0.1

# SSH forwarding
iptables -t nat -A PREROUTING -p tcp --dport $SSH_PORT -j DNAT --to-destination $VPN_IP:22
iptables -t nat -A POSTROUTING -p tcp -d $VPN_IP --dport 22 -j SNAT --to-source 10.8.0.1

# Open firewall ports
ufw allow $WINBOX_PORT/tcp
ufw allow $WEBFIG_PORT/tcp
ufw allow $SSH_PORT/tcp

# Step 6: Save iptables rules
echo "[6/6] Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4

echo ""
echo "=== SUCCESS! Client $CLIENT_NAME Added ==="
echo ""
echo "CLIENT INFORMATION:"
echo "- Client Name: $CLIENT_NAME"
echo "- VPN IP: $VPN_IP"
echo "- Certificate files: /root/$CLIENT_NAME/"
echo ""
echo "PUBLIC ACCESS PORTS:"
echo "- Winbox: 16.28.86.103:$WINBOX_PORT"
echo "- WebFig: http://16.28.86.103:$WEBFIG_PORT"
echo "- SSH: ssh admin@16.28.86.103 -p $SSH_PORT"
echo ""
echo "NEXT STEPS:"
echo "1. Download certificate files from VPS"
echo "2. Upload them to the MikroTik router"
echo "3. Configure the router (see instructions below)"
echo ""
echo "=== CERTIFICATE DOWNLOAD COMMANDS ==="
echo "Run these on your local computer:"
echo "mkdir ~/Desktop/$CLIENT_NAME"
echo "scp root@16.28.86.103:/root/$CLIENT_NAME/* ~/Desktop/$CLIENT_NAME/"
echo ""
echo "=== MIKROTIK CONFIGURATION COMMANDS ==="
echo "Run these on the MikroTik router terminal:"
echo ""
echo "# Import certificates"
echo "/certificate import file-name=ca.crt passphrase=\"\""
echo "/certificate import file-name=$CLIENT_NAME.crt passphrase=\"\""
echo "/certificate import file-name=$CLIENT_NAME.key passphrase=\"\""
echo ""
echo "# Create OpenVPN client"
echo "/interface ovpn-client add name=ovpn-to-vps \\"
echo "  connect-to=16.28.86.103 port=1194 mode=ip \\""
echo "  user=$CLIENT_NAME password=\"\" \\"
echo "  auth=sha1 cipher=aes256 \\"
echo "  certificate=$CLIENT_NAME.crt_0 \\"
echo "  verify-server-certificate=no add-default-route=no disabled=no"
echo ""
echo "# Configure services (security)"
echo "/ip service set winbox disabled=no port=8291 address=10.8.0.1"
echo "/ip service set www disabled=no port=80 address=10.8.0.1"
echo "/ip service set ssh disabled=no port=22 address=10.8.0.1"
echo ""
echo "# Add firewall rules"
echo "/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8291 action=accept place-before=0 comment=\"Winbox via VPS\""
echo "/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=80 action=accept place-before=0 comment=\"WebFig via VPS\""
echo "/ip firewall filter add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=22 action=accept place-before=0 comment=\"SSH via VPS\""
echo ""
echo "=== VERIFICATION COMMANDS ==="
echo "After configuration, verify on MikroTik:"
echo "/interface ovpn-client print status"
echo "/ip address print where interface=ovpn-to-vps"
echo "/log print where topics~\"ovpn\""
echo ""
echo "You should see 'connected' status and IP address $VPN_IP"
EOF
```

**Make the script executable:**
```bash
chmod +x /usr/local/bin/add-mikrotik-client
```

### Step 2: Plan Your Router Assignments

Before adding routers, plan your IP and port assignments:

| Router Name | VPN IP | Winbox Port | WebFig Port | SSH Port | RouterOS |
|-------------|---------|-------------|-------------|----------|----------|
| mikrotik-client-02 | 10.8.0.3 | 8291 | 8080 | 22022 | 6.49.10 |
| mikrotik-client-04 | 10.8.0.7 | 8295 | 8085 | 22030 | 7.x |
| customer-next | 10.8.0.8 | 8296 | 8086 | 22032 | TBD |
| customer-after | 10.8.0.9 | 8297 | 8087 | 22034 | TBD |

**Rules:**
- VPN IPs: 10.8.0.8, 10.8.0.9, 10.8.0.10, etc. (avoid .1, .2, .3, .7 already used)
- Winbox Ports: 8296, 8297, 8298, etc. (avoid 8291, 8295 already used)
- WebFig Ports: 8086, 8087, 8088, etc. (avoid 8080, 8085 already used)
- SSH Ports: 22032, 22034, 22036, etc. (avoid 22022, 22030 already used)

**Important:** RouterOS 6 and 7 have different command syntax!

### Step 3: Add a New Router (Manual Method - PROVEN TO WORK)

**On your VPS, create certificates the exact way that works:**

```bash
# Go to the correct easy-rsa directory
cd /etc/openvpn/easy-rsa

# Create the certificate (replace customer-abc with your client name)
./easyrsa build-client-full customer-abc nopass

# Set static VPN IP
mkdir -p /etc/openvpn/server/ccd
echo "ifconfig-push 10.8.0.8 255.255.255.0" > /etc/openvpn/server/ccd/customer-abc

# Prepare files for download
mkdir -p /root/customer-abc
cp /etc/openvpn/server/ca.crt /root/customer-abc/
cp pki/issued/customer-abc.crt /root/customer-abc/
cp pki/private/customer-abc.key /root/customer-abc/

# Verify files are there
ls -la /root/customer-abc/

# Add port forwarding (example: 8296, 8086, 22032)
iptables -t nat -A PREROUTING -p tcp --dport 8296 -j DNAT --to-destination 10.8.0.8:8291
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.8 --dport 8291 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 8086 -j DNAT --to-destination 10.8.0.8:80
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.8 --dport 80 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 22032 -j DNAT --to-destination 10.8.0.8:22
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.8 --dport 22 -j SNAT --to-source 10.8.0.1

# Open firewall ports
ufw allow 8296/tcp
ufw allow 8086/tcp
ufw allow 22032/tcp

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Restart OpenVPN server
systemctl restart openvpn-server@server
```

### Step 4: Download Certificates to Your Computer

**IMPORTANT: Download files individually (wildcard * doesn't work reliably)**

**On your local computer (Mac/PC):**
```bash
# Create directory
mkdir ~/Desktop/customer-abc

# Download each file individually (this method WORKS)
scp root@16.28.86.103:/root/customer-abc/ca.crt ~/Desktop/customer-abc/
scp root@16.28.86.103:/root/customer-abc/customer-abc.crt ~/Desktop/customer-abc/
scp root@16.28.86.103:/root/customer-abc/customer-abc.key ~/Desktop/customer-abc/

# Verify download
ls -la ~/Desktop/customer-abc/
```

You should now have:
- `ca.crt` (700 bytes)
- `customer-abc.crt` (~2500 bytes)
- `customer-abc.key` (~241 bytes)

### Step 5: Configure the Customer's MikroTik Router

**Upload certificates to MikroTik:**
1. Connect to the MikroTik via Winbox (local network)
2. Go to **Files** menu
3. Drag and drop all 3 certificate files

**IMPORTANT: RouterOS 6 and 7 have different syntax!**

#### For RouterOS 6 (6.49.x):

```bash
# Import certificates
/certificate import file-name=ca.crt passphrase=""
/certificate import file-name=customer-abc.crt passphrase=""
/certificate import file-name=customer-abc.key passphrase=""

# Create OpenVPN client
/interface ovpn-client add name=ovpn-to-vps \
  connect-to=16.28.86.103 port=1194 mode=ip \
  user=customer-abc password="" \
  auth=sha1 cipher=aes256 \
  certificate=customer-abc.crt_0 \
  verify-server-certificate=no add-default-route=no disabled=no

# Configure services for security
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
# Import certificates
/certificate import file-name=ca.crt passphrase=""
/certificate import file-name=customer-abc.crt passphrase=""
/certificate import file-name=customer-abc.key passphrase=""

# Create OpenVPN client (note the forward slashes!)
/interface/ovpn-client/add name=ovpn-to-vps \
  connect-to=16.28.86.103 port=1194 mode=ip \
  user=customer-abc password="" \
  auth=sha1 cipher=aes256-cbc \
  certificate=customer-abc.crt_0 \
  verify-server-certificate=no add-default-route=no disabled=no

# Configure services for security
/ip/service/set winbox disabled=no port=8291 address=10.8.0.1
/ip/service/set www disabled=no port=80 address=10.8.0.1
/ip/service/set ssh disabled=no port=22 address=10.8.0.1

# Add firewall rules
/ip/firewall/filter/add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=8291 action=accept place-before=0 comment="Winbox via VPS"
/ip/firewall/filter/add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=80 action=accept place-before=0 comment="WebFig via VPS"
/ip/firewall/filter/add chain=input in-interface=ovpn-to-vps protocol=tcp dst-port=22 action=accept place-before=0 comment="SSH via VPS"
```

### Step 6: Verify Connection

**On RouterOS 6:**
```bash
/interface ovpn-client print status
/ip address print where interface=ovpn-to-vps
/log print where topics~"ovpn"
```

**On RouterOS 7:**
```bash
/interface/ovpn-client/print detail
/interface/ovpn-client/monitor [find name="ovpn-to-vps"] once
/ip/address/print where interface=ovpn-to-vps
/log/print where topics~"ovpn"
```

**You should see:**
- Status: `connected` 
- IP address: assigned VPN IP on interface `ovpn-to-vps`
- Log: `using encoding - AES-256-CBC/SHA1` and `connected`

**IMPORTANT: Note the actual assigned IP address!** 
Sometimes the static IP assignment (CCD) doesn't work and the client gets a dynamic IP from the pool. This is fine, but you need to update your VPS port forwarding rules to match the actual IP.

**On VPS:**
```bash
cat /etc/openvpn/server/openvpn-status.log
ping [ACTUAL_IP]  # Use the IP you see on the MikroTik
```

### Step 7: Test Remote Access

**Now you can connect remotely:**
- **Winbox:** Connect to `16.28.86.103:8293`
- **WebFig:** Open `http://16.28.86.103:8083`
- **SSH:** `ssh admin@16.28.86.103 -p 22026`

## Part 3: Troubleshooting Guide

### Problem: Adding new router breaks existing routers

**Symptoms:** You add a new router and it works, but previously working routers stop working

**Cause:** Using `iptables -t nat -F` removes ALL existing NAT rules, breaking other routers

**Solution - Rebuild ALL router rules at once:**
```bash
# CRITICAL: Always rebuild ALL routers when fixing one
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Router #2 (mikrotik-client-02) - 10.8.0.3
iptables -t nat -A PREROUTING -p tcp --dport 8291 -j DNAT --to-destination 10.8.0.3:8291
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 8291 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.8.0.3:80
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 80 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 22022 -j DNAT --to-destination 10.8.0.3:22
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.3 --dport 22 -j SNAT --to-source 10.8.0.1

# Router #3 (mikrotik-client-04) - 10.8.0.5
iptables -t nat -A PREROUTING -p tcp --dport 8295 -j DNAT --to-destination 10.8.0.5:8291
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.5 --dport 8291 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 8085 -j DNAT --to-destination 10.8.0.5:80
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.5 --dport 80 -j SNAT --to-source 10.8.0.1
iptables -t nat -A PREROUTING -p tcp --dport 22030 -j DNAT --to-destination 10.8.0.5:22
iptables -t nat -A POSTROUTING -p tcp -d 10.8.0.5 --dport 22 -j SNAT --to-source 10.8.0.1

# Add more routers here as needed...

iptables-save > /etc/iptables/rules.v4
```

### Problem: MikroTik gets wrong VPN IP (not the static IP you assigned)

**Symptoms:** You set static IP 10.8.0.7 in CCD but MikroTik gets 10.8.0.5

**Solution:** Use the method above but replace the IP addresses with the actual assigned IPs

### Problem: "TLS failed" in MikroTik logs

**Solution:**
1. Check certificate has private key: `/certificate print` (look for K flag)
2. If no K flag, re-import the `.key` file: `/certificate import file-name=customer-abc.key passphrase=""`
3. RouterOS 6: Use `auth=sha1 cipher=aes256`
4. RouterOS 7: Use `auth=sha1 cipher=aes256-cbc`

### Problem: Winbox "Router refused connection"

**Solution:**
1. Check VPS port forwarding points to correct IP: `iptables -t nat -L PREROUTING`
2. Check VPS SNAT rules: `iptables -t nat -L POSTROUTING`
3. Check MikroTik service restrictions: `/ip/service/print where name=winbox`
4. Check MikroTik firewall allows VPN interface: `/ip/firewall/filter/print where dst-port=8291`

### Problem: OpenVPN client won't connect

**Solution:**
1. Check VPS server status: `systemctl status openvpn-server@server`
2. Check MikroTik certificate name: Use exact name from `/certificate print`
3. For RouterOS 6.49.10: Ensure server has `tls-version-min 1.0` and `compat-mode 2.4.0`
4. RouterOS 7: Use forward slash syntax `/interface/ovpn-client/add`

### Problem: Can't access via public IP but VPN works

**Solution:**
1. Missing SNAT rule on VPS (traffic shows wrong source IP to MikroTik)
2. MikroTik services restricted to wrong IP address
3. Port forwarding points to wrong VPN IP
4. Firewall blocking the connection

## Part 4: Managing Your Service

### Current Router List

Keep track of your routers:

| Router Name | Customer | VPN IP | Winbox | WebFig | SSH | RouterOS | Status |
|-------------|----------|---------|---------|---------|-----|----------|---------|
| mikrotik-test | Test Router | 10.8.0.2 | - | - | - | 6.49.18 | Active |
| mikrotik-client-02 | Test Router 2 | 10.8.0.3 | 8291 | 8080 | 22022 | 6.49.10 | Active |
| mikrotik-client-04 | Test Router 3 | 10.8.0.5 | 8295 | 8085 | 22030 | 7.x | Active |

### Adding More Routers

For each new router:
1. Run: `add-mikrotik-client <name> <vpn-ip> <winbox-port> <webfig-port> <ssh-port>`
2. Download certificates
3. Configure MikroTik with provided commands
4. Test connection
5. Update your router list

### Port Assignment Strategy

**Next available ports:**
- VPN IPs: 10.8.0.8, 10.8.0.9, 10.8.0.10...
- Winbox: 8296, 8297, 8298...
- WebFig: 8086, 8087, 8088...
- SSH: 22032, 22034, 22036...

### Business Operations

**For customers:**
1. Give them their unique connection details:
   - Winbox: `16.28.86.103:XXXX`
   - WebFig: `http://16.28.86.103:XXXX`
2. You can access their router anytime for support
3. Charge monthly subscription ($20-50/month per router)

**Security:**
- Each router has unique certificates
- Routers can't access each other
- All traffic encrypted through VPN
- You can revoke access by removing certificates

## Part 5: Current Working Setup

### Verified Working Configuration

✅ **VPS OpenVPN Server**: 16.28.86.103:1194  
✅ **Router #2**: mikrotik-client-02 (RouterOS 6.49.10) - VPN IP: 10.8.0.3  
✅ **Router #3**: mikrotik-client-04 (RouterOS 7.x) - VPN IP: 10.8.0.5  

**Remote Access URLs:**
- **Router #2**: http://16.28.86.103:8080 (Winbox: 8291, SSH: 22022)
- **Router #3**: http://16.28.86.103:8085 (Winbox: 8295, SSH: 22030)

### Key Lessons Learned

1. **RouterOS 6 vs 7 Syntax**: Different command structures require different approaches
2. **Static IP Assignment**: CCD doesn't always work; use actual assigned IPs
3. **NAT Rule Management**: Never use `iptables -F` without rebuilding ALL router rules
4. **Certificate Download**: Use individual file downloads, not wildcards
5. **Troubleshooting Order**: VPS connectivity → Certificate import → VPN connection → NAT rules → Service restrictions

## Part 6: Next Steps

### Immediate Actions
1. Create a customer database/spreadsheet with current router details
2. Set up monitoring for connection status
3. Create customer onboarding documentation
4. Test adding a 4th router using the proven process

### Business Scaling
1. Create web interface for customer management
2. Automate billing and certificate management
3. Set up monitoring alerts for disconnected routers
4. Create customer portal for connection status

### Technical Improvements
1. Add certificate auto-renewal
2. Implement connection monitoring
3. Create backup VPS for redundancy
4. Add bandwidth monitoring per router

## Summary

You now have:
- ✅ Working MikroTik remote access service
- ✅ Automation script for adding new routers
- ✅ Port forwarding for direct Winbox/WebFig access
- ✅ Secure certificate-based authentication
- ✅ Scalable architecture for multiple customers

The system is ready for business use. Each new customer takes 5 minutes to set up using the automation script.
