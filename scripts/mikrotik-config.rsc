# MikroTik RouterOS Configuration Script
# For connecting to VPS-based OpenVPN server
# VPS IP: 45.93.94.98

# This script should be run after uploading and importing certificates

# Variables (adjust as needed)
:local vpnServerIP "45.93.94.98"
:local vpnPort "1194"
:local clientName "ovpn-client-vps"
:local certName "client.crt_0"  # Adjust based on imported certificate name

# Create OpenVPN client interface
/interface ovpn-client
add name=$clientName \
    connect-to=$vpnServerIP \
    port=$vpnPort \
    mode=ip \
    cipher=aes256 \
    auth=sha1 \
    certificate=$certName \
    verify-server-certificate=yes \
    require-client-certificate=yes \
    add-default-route=no \
    disabled=no

# Wait for interface to come up
:delay 10s

# Add firewall rules to allow management from VPN network
/ip firewall filter
add chain=input src-address=10.8.0.0/24 action=accept place-before=0 \
    comment="Allow management from OpenVPN network"

# Add firewall rules for VPN traffic forwarding
/ip firewall filter
add chain=forward in-interface=$clientName action=accept \
    comment="Allow traffic from OpenVPN"
add chain=forward out-interface=$clientName action=accept \
    comment="Allow traffic to OpenVPN"

# Optional: Add NAT rule if you need to masquerade traffic through VPN
# Uncomment the following lines if needed:
# /ip firewall nat
# add chain=srcnat out-interface=$clientName action=masquerade \
#     comment="Masquerade traffic through OpenVPN"

# Optional: Add specific routes through VPN
# Uncomment and adjust as needed:
# /ip route
# add dst-address=192.168.100.0/24 gateway=$clientName \
#     comment="Route specific network through VPN"

# Create script to monitor VPN connection
/system script
add name=check-vpn-connection source={
    :local vpnInterface "ovpn-client-vps"
    :if ([/interface get $vpnInterface running] = false) do={
        :log warning "OpenVPN client disconnected, attempting reconnect"
        /interface ovpn-client disable $vpnInterface
        :delay 5s
        /interface ovpn-client enable $vpnInterface
    } else={
        :log info "OpenVPN client is connected"
    }
}

# Schedule the monitoring script to run every 2 minutes
/system scheduler
add name=vpn-monitor interval=2m on-event=check-vpn-connection \
    comment="Monitor OpenVPN connection status"

# Enable SNMP for monitoring (optional)
# Uncomment if you want SNMP monitoring:
# /snmp
# set enabled=yes contact="admin@yourdomain.com" location="Remote Site"
# /snmp community
# set public address=10.8.0.0/24

# Create backup script for configuration
/system script
add name=backup-config source={
    :local backupName ("backup-" . [/system clock get date] . "-" . [/system clock get time])
    :set backupName [:tostr [:pick $backupName 0 [:find $backupName ":"]]]
    /export file=$backupName
    :log info ("Configuration backup created: " . $backupName . ".rsc")
}

# Schedule daily backup at 2 AM
/system scheduler
add name=daily-backup interval=1d start-time=02:00:00 on-event=backup-config \
    comment="Daily configuration backup"

# Set up logging for OpenVPN
/system logging
add topics=ovpn action=memory

# Display current status
:put "OpenVPN client configuration completed!"
:put ("Interface name: " . $clientName)
:put ("Server: " . $vpnServerIP . ":" . $vpnPort)
:put ""
:put "To check connection status:"
:put "/interface ovpn-client print status"
:put "/log print where topics~\"ovpn\""
:put ""
:put "To monitor traffic:"
:put ("/interface monitor-traffic interface=" . $clientName)
