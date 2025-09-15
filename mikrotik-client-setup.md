# MikroTik Client Setup Guide

## Overview
This guide explains how to configure a MikroTik router as an OpenVPN client to connect to your VPS-based remote access service.

## Prerequisites
- MikroTik router with RouterOS
- Access to router (Winbox, WebFig, or SSH)
- Client certificate files from VPS server
- VPS OpenVPN server running on 16.28.86.103

## Step-by-Step Configuration

### 1. Prepare Certificate Files

From your VPS server, you should have received a `.ovpn` file. Extract the following components:

**Example client.ovpn file structure:**
```
client
dev tun
proto tcp
remote 16.28.86.103 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3

<ca>
-----BEGIN CERTIFICATE-----
[CA Certificate Content]
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
[Client Certificate Content]
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
[Client Private Key Content]
-----END PRIVATE KEY-----
</key>

<tls-auth>
-----BEGIN OpenVPN Static key V1-----
[TLS Auth Key Content]
-----END OpenVPN Static key V1-----
</tls-auth>
key-direction 1
```

### 2. Create Certificate Files

Create separate files for each certificate component:

**ca.crt** - Extract content between `<ca>` and `</ca>`
**client.crt** - Extract content between `<cert>` and `</cert>`
**client.key** - Extract content between `<key>` and `</key>`
**ta.key** - Extract content between `<tls-auth>` and `</tls-auth>`

### 3. Upload Certificates to MikroTik

#### Method 1: Using Winbox
1. Open Winbox and connect to your MikroTik router
2. Go to **Files** menu
3. Drag and drop the certificate files (ca.crt, client.crt, client.key, ta.key)

#### Method 2: Using FTP
```bash
# Enable FTP on MikroTik first
/ip service enable ftp

# Upload files via FTP client
ftp 192.168.1.1  # Your MikroTik IP
# Login with admin credentials
# put ca.crt
# put client.crt
# put client.key
# put ta.key
```

#### Method 3: Using WebFig
1. Access WebFig via web browser (http://router-ip)
2. Go to **Files**
3. Click **Upload** and select each certificate file

### 4. Import Certificates

Connect to MikroTik via terminal (Winbox Terminal, SSH, or WebFig Terminal):

```bash
# Import CA certificate
/certificate import file-name=ca.crt passphrase=""

# Import client certificate
/certificate import file-name=client.crt passphrase=""

# Import client private key
/certificate import file-name=client.key passphrase=""

# Import TLS auth key (this will be referenced by filename)
# Note: ta.key is not imported as certificate, just kept as file

# Verify certificates are imported
/certificate print
```

You should see the imported certificates listed with their names.

### 5. Create OpenVPN Client Interface

#### Using Winbox:
1. Go to **PPP** → **Interface**
2. Click **+** (Add) → **OVPN Client**
3. Configure the following settings:

**General Tab:**
- **Name:** ovpn-client-vps
- **Connect To:** 16.28.86.103
- **Port:** 1194
- **Mode:** ip
- **User:** (leave empty for certificate auth)
- **Password:** (leave empty for certificate auth)

**Dial Out Tab:**
- **Phone:** (leave empty)
- **Callback:** (leave empty)

**Advanced Tab:**
- **Auth:** sha1
- **Cipher:** aes256
- **Certificate:** Select your imported client certificate

#### Using Terminal:
```bash
/interface ovpn-client add \
    name=ovpn-client-vps \
    connect-to=16.28.86.103 \
    port=1194 \
    mode=ip \
    cipher=aes256 \
    auth=sha1 \
    certificate=client.crt_0 \
    add-default-route=no \
    disabled=no
```

### 6. Configure Advanced Settings

#### Add TLS Authentication:
Since MikroTik doesn't directly support TLS-auth in the interface, we need to add it manually:

```bash
# Add TLS auth key reference
/interface ovpn-client set ovpn-client-vps tls-auth=ta.key
```

#### Set Additional Options:
```bash
/interface ovpn-client set ovpn-client-vps \
    verify-server-certificate=yes \
    require-client-certificate=yes
```

### 7. Enable the Interface

```bash
# Enable the OpenVPN client interface
/interface ovpn-client enable ovpn-client-vps

# Check interface status
/interface ovpn-client print status
```

### 8. Configure Routing (Optional)

If you want to route specific traffic through the VPN:

```bash
# Add route for management traffic through VPN
/ip route add dst-address=10.8.0.0/24 gateway=ovpn-client-vps

# Add route for specific networks (example)
/ip route add dst-address=192.168.100.0/24 gateway=ovpn-client-vps
```

For all traffic through VPN (not recommended for production):
```bash
/ip route add dst-address=0.0.0.0/0 gateway=ovpn-client-vps distance=1
```

### 9. Configure Firewall Rules

Allow management access through VPN:

```bash
# Allow management from VPN network
/ip firewall filter add chain=input src-address=10.8.0.0/24 action=accept place-before=0

# Allow forwarding through VPN interface
/ip firewall filter add chain=forward in-interface=ovpn-client-vps action=accept
/ip firewall filter add chain=forward out-interface=ovpn-client-vps action=accept
```

### 10. NAT Configuration (If Required)

If you need to NAT traffic through the VPN:

```bash
# Masquerade traffic going through VPN
/ip firewall nat add chain=srcnat out-interface=ovpn-client-vps action=masquerade
```

## Verification and Troubleshooting

### Check Connection Status

```bash
# Check interface status
/interface ovpn-client print status

# Check if interface is running
/interface print where name=ovpn-client-vps

# Check assigned IP
/ip address print where interface=ovpn-client-vps
```

### Monitor Connection

```bash
# View OpenVPN logs
/log print where topics~"ovpn"

# Monitor interface statistics
/interface monitor-traffic interface=ovpn-client-vps
```

### Test Connectivity

```bash
# Ping VPS server through tunnel
/ping 10.8.0.1

# Test routing
/ip route print where gateway=ovpn-client-vps
```

## Common Issues and Solutions

### 1. Connection Fails
**Symptoms:** Interface shows "disconnected"
**Solutions:**
- Check firewall rules on both ends
- Verify certificate validity
- Check server logs on VPS
- Ensure correct server IP and port

### 2. Certificate Errors
**Symptoms:** Authentication failures
**Solutions:**
- Re-import certificates
- Check certificate names match configuration
- Verify certificate validity dates

### 3. Routing Issues
**Symptoms:** Connected but no traffic flows
**Solutions:**
- Check routing table
- Verify firewall rules
- Check NAT configuration
- Ensure server pushes correct routes

### 4. Performance Issues
**Symptoms:** Slow connection
**Solutions:**
- Check CPU usage on MikroTik
- Monitor interface statistics
- Consider using hardware with AES acceleration
- Check network latency to VPS

## Advanced Configuration

### Multiple VPN Connections
You can configure multiple OpenVPN clients for redundancy:

```bash
# Create backup connection
/interface ovpn-client add \
    name=ovpn-client-backup \
    connect-to=backup-server-ip \
    port=1194 \
    mode=ip \
    cipher=aes256 \
    auth=sha1 \
    certificate=backup-client-cert \
    disabled=yes

# Enable backup when primary fails
# This requires scripting for automatic failover
```

### Connection Monitoring Script
```bash
# Create script to monitor VPN connection
/system script add name=check-vpn source={
    :if ([/interface get ovpn-client-vps running] = false) do={
        :log warning "OpenVPN client disconnected, attempting reconnect"
        /interface ovpn-client disable ovpn-client-vps
        :delay 5s
        /interface ovpn-client enable ovpn-client-vps
    }
}

# Schedule script to run every minute
/system scheduler add name=vpn-monitor interval=1m on-event=check-vpn
```

## Security Best Practices

1. **Use strong certificates:** Ensure certificates have proper key lengths
2. **Regular updates:** Keep RouterOS updated
3. **Monitor connections:** Set up logging and monitoring
4. **Limit access:** Use firewall rules to restrict VPN access
5. **Certificate rotation:** Regularly rotate certificates
6. **Backup configuration:** Keep configuration backups

## Maintenance

### Regular Tasks:
- Check connection status
- Monitor logs for errors
- Update RouterOS firmware
- Rotate certificates before expiry
- Review firewall rules

### Certificate Renewal:
When certificates are renewed on the VPS:
1. Download new client configuration
2. Upload new certificates to MikroTik
3. Import new certificates
4. Update OpenVPN client configuration
5. Test connection

## Next Steps

1. Test the connection thoroughly
2. Set up monitoring and alerting
3. Create backup connections
4. Document specific network requirements
5. Train users on troubleshooting procedures
