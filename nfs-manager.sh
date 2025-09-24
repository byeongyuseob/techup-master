#!/bin/bash

# NFS Server Management Script
# Usage: nfs-manager.sh {up|down|status|restart}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# NFS related services
NFS_SERVICES=(
    "rpcbind"
    "nfs-server"
)

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

# Function to start NFS services
start_nfs() {
    print_status $GREEN "🚀 Starting NFS Server..."

    # Create NFS directories if they don't exist
    print_status $YELLOW "Creating NFS directories..."
    mkdir -p /nfs/shared /srv/nfs_share
    chown nobody:nobody /nfs/shared
    chmod 755 /nfs/shared /srv/nfs_share

    # Create sample files for testing
    print_status $YELLOW "Creating test files..."

    # Create files in /nfs/shared
    cat > /nfs/shared/test.txt << EOF
================================================================================
TECH UP DAY 평촌IDC NFS Test용 파일입니다.
================================================================================

이 파일은 NFS 마운트 및 공유 정상 여부를 확인하기 위해 작성되었습니다.

내용이 정상적으로 보이면 NFS 서버와 클라이언트 간의 공유가 올바르게 작동하고 있는 것입니다.

--------------------------------------------------------------------------------
[서버 정보]
- 생성일시: $(date '+%Y년 %m월 %d일 %H:%M:%S')
- 서버 호스트명: $(hostname)
- 서버 IP: $(hostname -I | awk '{print $1}')
- NFS 공유 경로: /nfs/shared
--------------------------------------------------------------------------------
EOF

    # Set proper permissions
    chown -R nobody:nobody /nfs/shared
    chmod -R 644 /nfs/shared/*
    chmod -R 755 /srv/nfs_share

    print_status $GREEN "✅ Test files created successfully"

    # Configure NFS exports
    print_status $YELLOW "Configuring NFS exports..."
    cat > /etc/exports << EOF
# NFS Export Configuration
# Format: directory client(options)

# Allow access from any IP address
/nfs/shared     *(rw,sync,no_root_squash,no_subtree_check)
/srv/nfs_share  *(rw,sync,no_root_squash,no_subtree_check)
EOF

    print_status $GREEN "✅ NFS exports configured"

    # Start services in order
    for service in "${NFS_SERVICES[@]}"; do
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

    # Reload exports
    print_status $YELLOW "Reloading NFS exports..."
    exportfs -ra


    print_status $GREEN "🎉 NFS Server is UP and running!"
    echo
    print_status $YELLOW "Current exports:"
    exportfs -v

    echo
    print_status $GREEN "📋 Client Mount Commands:"
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}On client servers (192.168.0.240), run these commands:${NC}"
    echo
    echo -e "${YELLOW}# Install NFS client${NC}"
    echo "yum install nfs-utils -y"
    echo
    echo -e "${YELLOW}# Create mount points${NC}"
    echo "mkdir -p /mnt/nfs_shared /mnt/nfs_share"
    echo
    echo -e "${YELLOW}# Mount NFS shares${NC}"
    echo "mount -t nfs ${SERVER_IP}:/nfs/shared /mnt/nfs_shared"
    echo "mount -t nfs ${SERVER_IP}:/srv/nfs_share /mnt/nfs_share"
    echo
    echo -e "${YELLOW}# Verify mounts${NC}"
    echo "df -h | grep nfs"
    echo "ls -la /mnt/nfs_shared/"
    echo "cat /mnt/nfs_shared/README.txt"
    echo
    echo -e "${YELLOW}# For permanent mounts, add to /etc/fstab:${NC}"
    echo "${SERVER_IP}:/nfs/shared /mnt/nfs_shared nfs defaults 0 0"
    echo "${SERVER_IP}:/srv/nfs_share /mnt/nfs_share nfs defaults 0 0"
}

# Function to stop NFS services
stop_nfs() {
    print_status $RED "🛑 Stopping NFS Server..."

    # Unexport all shares
    print_status $YELLOW "Unexporting all NFS shares..."
    exportfs -ua

    # Clean up exports file
    print_status $YELLOW "Cleaning up /etc/exports..."
    if [ -f /etc/exports ]; then
        mv /etc/exports /etc/exports.backup.$(date +%Y%m%d_%H%M%S)
        echo "# NFS exports disabled by nfs-manager" > /etc/exports
    fi

    # Stop services in reverse order
    for ((i=${#NFS_SERVICES[@]}-1; i>=0; i--)); do
        service="${NFS_SERVICES[i]}"
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


    print_status $RED "🔴 NFS Server is DOWN!"
}

# Function to show NFS status
show_status() {
    print_status $YELLOW "📊 NFS Server Status:"
    echo

    for service in "${NFS_SERVICES[@]}"; do
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

    echo
    print_status $YELLOW "Current exports:"
    exportfs -v 2>/dev/null || echo "No exports configured"


    echo
    print_status $YELLOW "RPC services:"
    rpcinfo -p localhost 2>/dev/null | head -5 || echo "RPC services not available"
}

# Function to restart NFS services
restart_nfs() {
    print_status $YELLOW "🔄 Restarting NFS Server..."
    stop_nfs
    sleep 2
    start_nfs
}

# Main script logic
case "$1" in
    up|start)
        start_nfs
        ;;
    down|stop)
        stop_nfs
        ;;
    status)
        show_status
        ;;
    restart)
        restart_nfs
        ;;
    *)
        echo "Usage: $0 {up|down|status|restart}"
        echo
        echo "Commands:"
        echo "  up/start   - Start NFS server and configure all settings"
        echo "  down/stop  - Stop NFS server and remove configurations"
        echo "  status     - Show current NFS server status"
        echo "  restart    - Restart NFS server"
        exit 1
        ;;
esac
