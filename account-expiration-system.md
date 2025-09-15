# MikroTik Remote Access - Account Expiration & Renewal System

## Overview

This system adds subscription management to your MikroTik remote access service, allowing you to:
- Set expiration dates for client accounts
- Automatically suspend expired accounts
- Provide renewal functionality
- Send expiration warnings
- Manage billing and payments

## Method 1: File-Based Expiration System

### Step 1: Update Client Creation Script

```bash
# Update the create-mikrotik-autoconfig script to include expiration dates
cat > /usr/local/bin/create-mikrotik-autoconfig-with-expiry << 'EOF'
#!/bin/bash
# MikroTik Remote Access - Client Setup with Expiration

CLIENT_NAME="$1"
VPN_IP="$2"
WINBOX_PORT="$3"
WEBFIG_PORT="$4"
SSH_PORT="$5"
EXPIRY_DAYS="${6:-30}"  # Default 30 days if not specified

if [ -z "$CLIENT_NAME" ] || [ -z "$VPN_IP" ] || [ -z "$WINBOX_PORT" ] || [ -z "$WEBFIG_PORT" ] || [ -z "$SSH_PORT" ]; then
    echo "Usage: create-mikrotik-autoconfig-with-expiry <client-name> <vpn-ip> <winbox-port> <webfig-port> <ssh-port> [expiry-days]"
    echo "Example: create-mikrotik-autoconfig-with-expiry customer-john 10.8.0.8 8296 8086 22032 30"
    exit 1
fi

# Calculate expiration date
EXPIRY_DATE=$(date -d "+$EXPIRY_DAYS days" '+%Y-%m-%d')
EXPIRY_TIMESTAMP=$(date -d "+$EXPIRY_DAYS days" '+%s')

echo "🚀 Creating client with expiration: $CLIENT_NAME (expires: $EXPIRY_DATE)"

# Run the original client creation script
create-mikrotik-autoconfig "$CLIENT_NAME" "$VPN_IP" "$WINBOX_PORT" "$WEBFIG_PORT" "$SSH_PORT"

# Add expiration data to client folder
cat > "/var/www/html/clients/$CLIENT_NAME/account.txt" << ACCOUNTEOF
CLIENT_NAME=$CLIENT_NAME
VPN_IP=$VPN_IP
WINBOX_PORT=$WINBOX_PORT
WEBFIG_PORT=$WEBFIG_PORT
SSH_PORT=$SSH_PORT
CREATED_DATE=$(date '+%Y-%m-%d')
EXPIRY_DATE=$EXPIRY_DATE
EXPIRY_TIMESTAMP=$EXPIRY_TIMESTAMP
STATUS=active
ACCOUNTEOF

# Add to global expiration tracking
echo "$CLIENT_NAME:$EXPIRY_TIMESTAMP:$EXPIRY_DATE:active" >> /var/log/client-expiration.log

echo ""
echo "✅ Client created with expiration:"
echo "   Expires: $EXPIRY_DATE ($EXPIRY_DAYS days)"
echo "   Status: Active"
echo ""

EOF

chmod +x /usr/local/bin/create-mikrotik-autoconfig-with-expiry
```

### Step 2: Create Account Management Scripts

```bash
# Create account suspension script
cat > /usr/local/bin/suspend-client << 'EOF'
#!/bin/bash
CLIENT_NAME="$1"

if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: suspend-client <client-name>"
    exit 1
fi

ACCOUNT_FILE="/var/www/html/clients/$CLIENT_NAME/account.txt"
if [ ! -f "$ACCOUNT_FILE" ]; then
    echo "Error: Client $CLIENT_NAME not found"
    exit 1
fi

# Load account details
source "$ACCOUNT_FILE"

echo "🔒 Suspending client: $CLIENT_NAME"

# Revoke OpenVPN certificate
cd /etc/openvpn/easy-rsa
./easyrsa revoke "$CLIENT_NAME"
./easyrsa gen-crl

# Remove from CCD (prevents reconnection)
rm -f "/etc/openvpn/server/ccd/$CLIENT_NAME"

# Remove from IP pool
sed -i "/^$CLIENT_NAME,/d" /etc/openvpn/server/ipp.txt

# Update account status
sed -i "s/STATUS=active/STATUS=suspended/" "$ACCOUNT_FILE"
sed -i "s/STATUS=expired/STATUS=suspended/" "$ACCOUNT_FILE"

# Remove NAT rules (blocks remote access)
fix-all-nat-rules

# Restart OpenVPN to apply changes
systemctl restart openvpn-server@server

# Create suspension notice
cat > "/var/www/html/clients/$CLIENT_NAME/suspended.html" << 'SUSPENDEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Account Suspended</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
        .container { max-width: 600px; margin: 0 auto; }
        .suspended { background: #f8d7da; color: #721c24; padding: 20px; border-radius: 5px; }
        .renew-btn { background: #28a745; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; display: inline-block; margin: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Account Suspended</h1>
        <div class="suspended">
            <h3>Your MikroTik remote access has been suspended</h3>
            <p><strong>Client:</strong> CLIENT_NAME</p>
            <p><strong>Reason:</strong> Account expired or payment overdue</p>
        </div>
        <a href="mailto:support@yourcompany.com?subject=Renew Account CLIENT_NAME" class="renew-btn">💳 Renew Account</a>
        <p>Contact support to renew your subscription and restore access.</p>
    </div>
</body>
</html>
SUSPENDEOF

sed -i "s/CLIENT_NAME/$CLIENT_NAME/g" "/var/www/html/clients/$CLIENT_NAME/suspended.html"

echo "✅ Client $CLIENT_NAME suspended successfully"
echo "   Certificate revoked and CRL updated"
echo "   NAT rules removed"
echo "   Suspension notice created"

EOF

chmod +x /usr/local/bin/suspend-client
```

```bash
# Create account renewal script
cat > /usr/local/bin/renew-client << 'EOF'
#!/bin/bash
CLIENT_NAME="$1"
RENEWAL_DAYS="${2:-30}"

if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: renew-client <client-name> [renewal-days]"
    echo "Example: renew-client customer-john 30"
    exit 1
fi

ACCOUNT_FILE="/var/www/html/clients/$CLIENT_NAME/account.txt"
if [ ! -f "$ACCOUNT_FILE" ]; then
    echo "Error: Client $CLIENT_NAME not found"
    exit 1
fi

# Load current account details
source "$ACCOUNT_FILE"

# Calculate new expiration date
NEW_EXPIRY_DATE=$(date -d "+$RENEWAL_DAYS days" '+%Y-%m-%d')
NEW_EXPIRY_TIMESTAMP=$(date -d "+$RENEWAL_DAYS days" '+%s')

echo "🔄 Renewing client: $CLIENT_NAME"
echo "   New expiry: $NEW_EXPIRY_DATE ($RENEWAL_DAYS days)"

# Update account file
sed -i "s/EXPIRY_DATE=.*/EXPIRY_DATE=$NEW_EXPIRY_DATE/" "$ACCOUNT_FILE"
sed -i "s/EXPIRY_TIMESTAMP=.*/EXPIRY_TIMESTAMP=$NEW_EXPIRY_TIMESTAMP/" "$ACCOUNT_FILE"
sed -i "s/STATUS=.*/STATUS=active/" "$ACCOUNT_FILE"

# Recreate client if suspended (regenerate certificate)
if [ "$STATUS" = "suspended" ] || [ "$STATUS" = "expired" ]; then
    echo "   Reactivating suspended/expired client..."
    
    # Recreate certificate
    cd /etc/openvpn/easy-rsa
    ./easyrsa build-client-full "$CLIENT_NAME" nopass
    
    # Recreate CCD
    mkdir -p /etc/openvpn/server/ccd
    echo "ifconfig-push $VPN_IP 255.255.255.0" > "/etc/openvpn/server/ccd/$CLIENT_NAME"
    
    # Add back to IP pool
    sed -i "/^$CLIENT_NAME,/d" /etc/openvpn/server/ipp.txt
    echo "$CLIENT_NAME,$VPN_IP" >> /etc/openvpn/server/ipp.txt
    
    # Update certificate files
    cp /etc/openvpn/server/ca.crt "/var/www/html/clients/$CLIENT_NAME/"
    cp "pki/issued/$CLIENT_NAME.crt" "/var/www/html/clients/$CLIENT_NAME/"
    cp "pki/private/$CLIENT_NAME.key" "/var/www/html/clients/$CLIENT_NAME/"
    
    # Rebuild NAT rules
    fix-all-nat-rules
    
    # Restart OpenVPN
    systemctl restart openvpn-server@server
fi

# Remove suspension notice
rm -f "/var/www/html/clients/$CLIENT_NAME/suspended.html"

# Log renewal
echo "$CLIENT_NAME:$NEW_EXPIRY_TIMESTAMP:$NEW_EXPIRY_DATE:renewed:$(date)" >> /var/log/client-renewals.log

# Create renewal confirmation
cat > "/var/www/html/clients/$CLIENT_NAME/renewed.html" << 'RENEWEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Account Renewed</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
        .container { max-width: 600px; margin: 0 auto; }
        .renewed { background: #d4edda; color: #155724; padding: 20px; border-radius: 5px; }
        .access-btn { background: #007cba; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; display: inline-block; margin: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Account Renewed</h1>
        <div class="renewed">
            <h3>Your MikroTik remote access has been renewed!</h3>
            <p><strong>Client:</strong> CLIENT_NAME</p>
            <p><strong>New Expiry:</strong> NEW_EXPIRY_DATE</p>
            <p><strong>Status:</strong> Active</p>
        </div>
        <a href="instructions.html" class="access-btn">🚀 Access Instructions</a>
        <p>Your remote access is now active. Use the link above for setup instructions.</p>
    </div>
</body>
</html>
RENEWEOF

sed -i "s/CLIENT_NAME/$CLIENT_NAME/g" "/var/www/html/clients/$CLIENT_NAME/renewed.html"
sed -i "s/NEW_EXPIRY_DATE/$NEW_EXPIRY_DATE/g" "/var/www/html/clients/$CLIENT_NAME/renewed.html"

echo "✅ Client $CLIENT_NAME renewed successfully"
echo "   New expiry: $NEW_EXPIRY_DATE"
echo "   Status: Active"
echo "   Renewal confirmation created"

EOF

chmod +x /usr/local/bin/renew-client
```

### Step 3: Create Expiration Monitoring Script

```bash
# Create expiration checker and auto-suspension script
cat > /usr/local/bin/check-expired-clients << 'EOF'
#!/bin/bash
# Check for expired clients and suspend them automatically

CURRENT_TIMESTAMP=$(date +%s)
WARN_DAYS=7
WARN_TIMESTAMP=$((CURRENT_TIMESTAMP + (WARN_DAYS * 24 * 60 * 60)))

echo "=== Checking Client Expirations ==="
echo "Current date: $(date)"
echo ""

EXPIRED_COUNT=0
WARNING_COUNT=0

# Check all client accounts
for account_file in /var/www/html/clients/*/account.txt; do
    [ -f "$account_file" ] || continue
    
    # Load account details
    source "$account_file"
    
    if [ "$EXPIRY_TIMESTAMP" -lt "$CURRENT_TIMESTAMP" ] && [ "$STATUS" = "active" ]; then
        # Account expired
        echo "🔒 EXPIRED: $CLIENT_NAME (expired: $EXPIRY_DATE)"
        suspend-client "$CLIENT_NAME"
        EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
        
        # Send expiration notification email (if configured)
        echo "Account $CLIENT_NAME has expired and been suspended." | \
        mail -s "Account Expired: $CLIENT_NAME" admin@yourcompany.com 2>/dev/null || true
        
    elif [ "$EXPIRY_TIMESTAMP" -lt "$WARN_TIMESTAMP" ] && [ "$STATUS" = "active" ]; then
        # Account expiring soon
        DAYS_LEFT=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / (24 * 60 * 60) ))
        echo "⚠️  WARNING: $CLIENT_NAME expires in $DAYS_LEFT days ($EXPIRY_DATE)"
        WARNING_COUNT=$((WARNING_COUNT + 1))
        
        # Create expiration warning
        cat > "/var/www/html/clients/$CLIENT_NAME/expiring.html" << 'WARNEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Account Expiring Soon</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
        .container { max-width: 600px; margin: 0 auto; }
        .warning { background: #fff3cd; color: #856404; padding: 20px; border-radius: 5px; }
        .renew-btn { background: #ffc107; color: #212529; padding: 15px 30px; text-decoration: none; border-radius: 5px; display: inline-block; margin: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚠️ Account Expiring Soon</h1>
        <div class="warning">
            <h3>Your MikroTik remote access expires soon!</h3>
            <p><strong>Client:</strong> CLIENT_NAME</p>
            <p><strong>Expires:</strong> EXPIRY_DATE</p>
            <p><strong>Days remaining:</strong> DAYS_LEFT</p>
        </div>
        <a href="mailto:support@yourcompany.com?subject=Renew Account CLIENT_NAME" class="renew-btn">💳 Renew Now</a>
        <p>Renew your subscription to avoid service interruption.</p>
    </div>
</body>
</html>
WARNEOF
        
        sed -i "s/CLIENT_NAME/$CLIENT_NAME/g" "/var/www/html/clients/$CLIENT_NAME/expiring.html"
        sed -i "s/EXPIRY_DATE/$EXPIRY_DATE/g" "/var/www/html/clients/$CLIENT_NAME/expiring.html"
        sed -i "s/DAYS_LEFT/$DAYS_LEFT/g" "/var/www/html/clients/$CLIENT_NAME/expiring.html"
        
    elif [ "$STATUS" = "active" ]; then
        # Account still active
        DAYS_LEFT=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / (24 * 60 * 60) ))
        echo "✅ ACTIVE: $CLIENT_NAME ($DAYS_LEFT days remaining)"
    else
        echo "🔒 SUSPENDED: $CLIENT_NAME (status: $STATUS)"
    fi
done

echo ""
echo "=== Summary ==="
echo "Expired and suspended: $EXPIRED_COUNT"
echo "Expiring within $WARN_DAYS days: $WARNING_COUNT"

# Log summary
echo "$(date): Checked expirations - $EXPIRED_COUNT expired, $WARNING_COUNT warnings" >> /var/log/expiration-checks.log

EOF

chmod +x /usr/local/bin/check-expired-clients
```

### Step 4: Create Account Status Checker

```bash
# Create client status checker
cat > /usr/local/bin/client-status << 'EOF'
#!/bin/bash
CLIENT_NAME="$1"

if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: client-status <client-name>"
    echo "       client-status all"
    exit 1
fi

if [ "$CLIENT_NAME" = "all" ]; then
    echo "=== All Client Status ==="
    for account_file in /var/www/html/clients/*/account.txt; do
        [ -f "$account_file" ] || continue
        source "$account_file"
        
        CURRENT_TIMESTAMP=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / (24 * 60 * 60) ))
        
        if [ "$EXPIRY_TIMESTAMP" -lt "$CURRENT_TIMESTAMP" ]; then
            STATUS_DISPLAY="🔒 EXPIRED"
        elif [ "$DAYS_LEFT" -le 7 ]; then
            STATUS_DISPLAY="⚠️  EXPIRING ($DAYS_LEFT days)"
        else
            STATUS_DISPLAY="✅ ACTIVE ($DAYS_LEFT days)"
        fi
        
        printf "%-20s | %-25s | %s | %s\n" "$CLIENT_NAME" "$STATUS_DISPLAY" "$EXPIRY_DATE" "$VPN_IP"
    done
else
    ACCOUNT_FILE="/var/www/html/clients/$CLIENT_NAME/account.txt"
    if [ ! -f "$ACCOUNT_FILE" ]; then
        echo "Error: Client $CLIENT_NAME not found"
        exit 1
    fi
    
    source "$ACCOUNT_FILE"
    
    CURRENT_TIMESTAMP=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / (24 * 60 * 60) ))
    
    echo "=== Client Status: $CLIENT_NAME ==="
    echo "VPN IP: $VPN_IP"
    echo "Created: $CREATED_DATE"
    echo "Expires: $EXPIRY_DATE"
    echo "Days remaining: $DAYS_LEFT"
    echo "Status: $STATUS"
    echo "Winbox: 16.28.86.103:$WINBOX_PORT"
    echo "WebFig: http://16.28.86.103:$WEBFIG_PORT"
    echo "SSH: 16.28.86.103:$SSH_PORT"
fi

EOF

chmod +x /usr/local/bin/client-status
```

### Step 5: Set Up Automated Expiration Checking

```bash
# Add cron job to check expiration daily
echo "0 2 * * * /usr/local/bin/check-expired-clients" >> /var/spool/cron/crontabs/root

# Or add to system crontab
echo "0 2 * * * root /usr/local/bin/check-expired-clients" >> /etc/crontab
```

## Usage Examples

### Create Client with Expiration
```bash
# Create client that expires in 30 days (default)
create-mikrotik-autoconfig-with-expiry customer-john 10.8.0.50 8350 8150 22080

# Create client that expires in 90 days
create-mikrotik-autoconfig-with-expiry premium-client 10.8.0.51 8351 8151 22081 90
```

### Manage Client Accounts
```bash
# Check status of all clients
client-status all

# Check specific client status
client-status customer-john

# Renew client for 30 more days
renew-client customer-john 30

# Suspend client immediately
suspend-client customer-john

# Check for expired clients (runs automatically daily)
check-expired-clients
```

## Benefits

✅ **Automated expiration management** - No manual tracking needed  
✅ **Automatic suspension** - Expired accounts are blocked immediately  
✅ **Flexible renewal** - Easy to extend subscriptions  
✅ **Warning system** - 7-day expiration warnings  
✅ **Professional notifications** - HTML pages for customers  
✅ **Complete audit trail** - All changes logged  
✅ **Scalable** - Handles unlimited clients  

This transforms your service into a proper subscription-based business with automated billing cycles!
