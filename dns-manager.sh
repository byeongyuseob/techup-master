#!/bin/bash

# DNS Server Management Script
# Usage: dns-manager.sh {up|down|status|restart}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# DNS related services
DNS_SERVICES=(
    "named"
)

# Configuration variables
DOMAIN="idctech.com"
TARGET_SERVER="192.168.0.240"
DNS_SERVER_IP="192.168.0.240"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if service exists
service_exists() {
    systemctl list-unit-files | grep -q "^$1"
}

# Function to create DNS zone file
create_dns_zone() {
    print_status $YELLOW "Creating DNS zone file for ${DOMAIN}..."

    cat > /var/named/${DOMAIN}.zone << EOF
\$TTL 86400
@   IN  SOA ns1.${DOMAIN}. admin.${DOMAIN}. (
        $(date +%Y%m%d)01  ; Serial
        3600            ; Refresh
        1800            ; Retry
        604800          ; Expire
        86400           ; Minimum TTL
)

; Name servers
@       IN  NS      ns1.${DOMAIN}.
@       IN  NS      ns2.${DOMAIN}.

; A records
@       IN  A       ${TARGET_SERVER}
www     IN  A       ${TARGET_SERVER}
ns1     IN  A       ${DNS_SERVER_IP}
ns2     IN  A       ${DNS_SERVER_IP}

; A records for subdomains
nsight  IN  A       ${TARGET_SERVER}

; CNAME records
ftp     IN  CNAME   www.${DOMAIN}.
mail    IN  CNAME   www.${DOMAIN}.
EOF

    chown named:named /var/named/${DOMAIN}.zone
    chmod 644 /var/named/${DOMAIN}.zone
    print_status $GREEN "✅ DNS zone file created"
}

# Function to create reverse DNS zone
create_reverse_zone() {
    print_status $YELLOW "Creating reverse DNS zone..."

    REVERSE_ZONE="0.168.192.in-addr.arpa"

    cat > /var/named/${REVERSE_ZONE}.zone << EOF
\$TTL 86400
@   IN  SOA ns1.${DOMAIN}. admin.${DOMAIN}. (
        $(date +%Y%m%d)01  ; Serial
        3600            ; Refresh
        1800            ; Retry
        604800          ; Expire
        86400           ; Minimum TTL
)

; Name servers
@       IN  NS      ns1.${DOMAIN}.
@       IN  NS      ns2.${DOMAIN}.

; PTR records
240     IN  PTR     www.${DOMAIN}.
240     IN  PTR     ns1.${DOMAIN}.
EOF

    chown named:named /var/named/${REVERSE_ZONE}.zone
    chmod 644 /var/named/${REVERSE_ZONE}.zone
    print_status $GREEN "✅ Reverse DNS zone created"
}

# Function to configure named.conf
configure_named() {
    print_status $YELLOW "Configuring named.conf..."

    # Backup original named.conf
    cp /etc/named.conf /etc/named.conf.backup

    cat > /etc/named.conf << 'EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { ::1; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query { any; };
    allow-recursion { any; };
    recursion yes;
    dnssec-enable yes;
    dnssec-validation yes;
    bindkeys-file "/etc/named.root.key";
    managed-keys-directory "/var/named/dynamic";
    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

    # Add our custom zones
    cat >> /etc/named.conf << EOF

// Custom zones
zone "${DOMAIN}" IN {
    type master;
    file "${DOMAIN}.zone";
    allow-update { none; };
};

zone "0.168.192.in-addr.arpa" IN {
    type master;
    file "0.168.192.in-addr.arpa.zone";
    allow-update { none; };
};
EOF

    print_status $GREEN "✅ named.conf configured"
}

# Function to setup web server for HTTP redirects
setup_web_server() {
    print_status $YELLOW "Setting up Apache web server for HTTP handling..."

    # Install Apache if not installed
    if ! rpm -q httpd &>/dev/null; then
        print_status $YELLOW "Installing Apache web server..."
        yum install -y httpd
    fi

    # Create virtual host configuration for main domain
    cat > /etc/httpd/conf.d/${DOMAIN}.conf << EOF
<VirtualHost *:80>
    ServerName www.${DOMAIN}
    ServerAlias ${DOMAIN}
    DocumentRoot /var/www/html/${DOMAIN}

    ProxyPreserveHost On

    # Specific path redirects
    ProxyPass /prom http://${TARGET_SERVER}:9090/
    ProxyPassReverse /prom http://${TARGET_SERVER}:9090/

    ProxyPass /alert http://${TARGET_SERVER}:9093/
    ProxyPassReverse /alert http://${TARGET_SERVER}:9093/

    ProxyPass /stats http://${TARGET_SERVER}:8404/
    ProxyPassReverse /stats http://${TARGET_SERVER}:8404/

    ProxyPass /nfs http://${TARGET_SERVER}/nfs
    ProxyPassReverse /nfs http://${TARGET_SERVER}/nfs

    ProxyPass /portainer http://${TARGET_SERVER}:9000/
    ProxyPassReverse /portainer http://${TARGET_SERVER}:9000/

    # Default redirect for root to target server
    ProxyPass / http://${TARGET_SERVER}/
    ProxyPassReverse / http://${TARGET_SERVER}/

    ErrorLog logs/${DOMAIN}_error.log
    CustomLog logs/${DOMAIN}_access.log combined
</VirtualHost>

# Virtual host for nsight subdomain
<VirtualHost *:80>
    ServerName nsight.${DOMAIN}

    ProxyPreserveHost On
    ProxyPass / http://${TARGET_SERVER}:3000/
    ProxyPassReverse / http://${TARGET_SERVER}:3000/

    ErrorLog logs/nsight.${DOMAIN}_error.log
    CustomLog logs/nsight.${DOMAIN}_access.log combined
</VirtualHost>
EOF

    # Create document root
    mkdir -p /var/www/html/${DOMAIN}

    # Create index page
    cat > /var/www/html/${DOMAIN}/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>IDC Tech - Redirecting...</title>
    <meta http-equiv="refresh" content="0;url=http://${TARGET_SERVER}:80/">
</head>
<body>
    <h1>Redirecting to IDC Tech Server...</h1>
    <p>If you are not automatically redirected, <a href="http://${TARGET_SERVER}:80/">click here</a>.</p>
</body>
</html>
EOF

    # Enable Apache modules
    systemctl enable httpd

    print_status $GREEN "✅ Web server configured"
}

# Function to start DNS services
start_dns() {
    print_status $GREEN "🚀 Starting DNS Server..."

    # Install bind if not installed
    if ! rpm -q bind &>/dev/null; then
        print_status $YELLOW "Installing BIND DNS server..."
        yum install -y bind bind-utils
    fi

    # Create DNS configuration
    configure_named
    create_dns_zone
    create_reverse_zone
    setup_web_server

    # Start DNS services
    for service in "${DNS_SERVICES[@]}"; do
        if service_exists "$service"; then
            print_status $YELLOW "Starting $service..."
            systemctl start "$service"
            systemctl enable "$service"
            if systemctl is-active --quiet "$service"; then
                print_status $GREEN "✅ $service started successfully"
            else
                print_status $RED "❌ Failed to start $service"
            fi
        else
            print_status $YELLOW "⚠️  $service not found, skipping..."
        fi
    done

    # Start Apache
    print_status $YELLOW "Starting Apache web server..."
    systemctl start httpd
    systemctl enable httpd
    if systemctl is-active --quiet httpd; then
        print_status $GREEN "✅ httpd started successfully"
    else
        print_status $RED "❌ Failed to start httpd"
    fi


    # Test DNS configuration
    print_status $YELLOW "Testing DNS configuration..."
    named-checkconf
    named-checkzone ${DOMAIN} /var/named/${DOMAIN}.zone

    print_status $GREEN "🎉 DNS Server is UP and running!"
    echo
    print_status $GREEN "📋 Configuration Summary:"
    echo -e "${GREEN}Domain: ${DOMAIN}${NC}"
    echo -e "${GREEN}DNS Server: ${DNS_SERVER_IP}${NC}"
    echo -e "${GREEN}Target Server: ${TARGET_SERVER}${NC}"
    echo
    print_status $YELLOW "Test commands:"
    echo "dig @${DNS_SERVER_IP} ${DOMAIN}"
    echo "dig @${DNS_SERVER_IP} www.${DOMAIN}"
    echo "curl -H 'Host: ${DOMAIN}' http://${DNS_SERVER_IP}/"
    echo
    print_status $YELLOW "Client DNS configuration:"
    echo "echo 'nameserver ${DNS_SERVER_IP}' > /etc/resolv.conf"
}

# Function to stop DNS services
stop_dns() {
    print_status $RED "🛑 Stopping DNS Server..."

    # Stop services
    for ((i=${#DNS_SERVICES[@]}-1; i>=0; i--)); do
        service="${DNS_SERVICES[i]}"
        if service_exists "$service"; then
            print_status $YELLOW "Stopping $service..."
            systemctl stop "$service"
            if ! systemctl is-active --quiet "$service"; then
                print_status $GREEN "✅ $service stopped successfully"
            else
                print_status $RED "❌ Failed to stop $service"
            fi
        fi
    done

    # Stop Apache
    print_status $YELLOW "Stopping Apache web server..."
    systemctl stop httpd


    print_status $RED "🔴 DNS Server is DOWN!"
}

# Function to show DNS status
show_status() {
    print_status $YELLOW "📊 DNS Server Status:"
    echo

    # Check DNS service
    for service in "${DNS_SERVICES[@]}"; do
        if service_exists "$service"; then
            if systemctl is-active --quiet "$service"; then
                print_status $GREEN "✅ $service: RUNNING"
            else
                print_status $RED "❌ $service: STOPPED"
            fi
        else
            print_status $YELLOW "⚠️  $service: NOT INSTALLED"
        fi
    done

    # Check Apache
    if systemctl is-active --quiet httpd; then
        print_status $GREEN "✅ httpd: RUNNING"
    else
        print_status $RED "❌ httpd: STOPPED"
    fi

    echo
    print_status $YELLOW "DNS Configuration:"
    if [ -f "/etc/named.conf" ]; then
        print_status $GREEN "✅ named.conf exists"
    else
        print_status $RED "❌ named.conf missing"
    fi

    if [ -f "/var/named/${DOMAIN}.zone" ]; then
        print_status $GREEN "✅ ${DOMAIN} zone file exists"
    else
        print_status $RED "❌ ${DOMAIN} zone file missing"
    fi


    echo
    print_status $YELLOW "Test DNS resolution:"
    dig +short @localhost ${DOMAIN} 2>/dev/null || echo "DNS resolution failed"
}

# Function to restart DNS services
restart_dns() {
    print_status $YELLOW "🔄 Restarting DNS Server..."
    stop_dns
    sleep 2
    start_dns
}

# Main script logic
case "$1" in
    up|start)
        start_dns
        ;;
    down|stop)
        stop_dns
        ;;
    status)
        show_status
        ;;
    restart)
        restart_dns
        ;;
    *)
        echo "Usage: $0 {up|down|status|restart}"
        echo
        echo "Commands:"
        echo "  up/start   - Start DNS server and configure domain resolution"
        echo "  down/stop  - Stop DNS server and remove configurations"
        echo "  status     - Show current DNS server status"
        echo "  restart    - Restart DNS server"
        echo
        echo "Configuration:"
        echo "  Domain: ${DOMAIN}"
        echo "  DNS Server: ${DNS_SERVER_IP}"
        echo "  Target Server: ${TARGET_SERVER}"
        exit 1
        ;;
esac
