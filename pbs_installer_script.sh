#!/bin/bash

#
# OpenPBS installation script
# Supports: Ubuntu 24.04 LTS
# GitHub: https://github.com/AhmedMejri1/OpenPBS-installation-script
#
# Usage:
#   bash pbs_install.sh
#   bash pbs_install.sh --node-type=server --cluster-name=mycluster
#   bash pbs_install.sh --node-type=compute --server-hostname=pbsserver
#
# Environment Variables:
#   PBS_VERSION - OpenPBS version to install (default: latest from master)
#   PBS_PREFIX - Installation prefix (default: /opt/pbs)
#

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="OpenPBS installation script"
GITHUB_REPO="https://github.com/AhmedMejri1/OpenPBS-installation-script"

# Default configuration
PBS_VERSION="${PBS_VERSION:-master}"
PBS_PREFIX="${PBS_PREFIX:-/opt/pbs}"
PBS_HOME="/var/spool/pbs"
DEFAULT_CLUSTER_NAME="pbs-cluster"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
NODE_TYPE=""
SERVER_HOSTNAME=""
CLUSTER_NAME="$DEFAULT_CLUSTER_NAME"
INTERACTIVE_MODE=true
ENABLE_ACCOUNTING=false
POSTGRES_PASSWORD=""
INSTALL_POSTGRES=false
FORCE_REINSTALL=false

# Logging setup
LOG_FILE="/tmp/pbs_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

#
# Utility Functions
#

print_header() {
    echo -e "${BLUE}"
    echo "================================================================"
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "================================================================"
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${GREEN}==>${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --node-type=TYPE          Node type: server, compute, or both (default: interactive)
    --server-hostname=HOST    PBS server hostname (required for compute nodes)
    --cluster-name=NAME       Cluster name (default: $DEFAULT_CLUSTER_NAME)
    --enable-accounting       Enable PBS accounting with PostgreSQL
    --postgres-password=PASS  PostgreSQL password for PBS accounting
    --install-postgres        Install PostgreSQL server
    --force-reinstall         Force reinstallation even if PBS is detected
    --without-interaction     Run in non-interactive mode
    --help                    Show this help message

Environment Variables:
    PBS_VERSION              OpenPBS version (default: master)
    PBS_PREFIX               Installation prefix (default: /opt/pbs)

Examples:
    # Interactive installation
    sudo bash pbs_install.sh

    # Install PBS server node
    sudo bash pbs_install.sh --node-type=server --cluster-name=mycluster

    # Install compute node
    sudo bash pbs_install.sh --node-type=compute --server-hostname=pbsserver

    # Install with accounting support
    sudo bash pbs_install.sh --node-type=server --enable-accounting --postgres-password=mypass

    # Non-interactive installation
    sudo bash pbs_install.sh --without-interaction --node-type=both

EOF
}

#
# System Detection Functions
#

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_VERSION_MAJOR=$(echo $VERSION_ID | cut -d. -f1)
    else
        print_error "Cannot detect operating system"
        exit 1
    fi

    print_info "Detected OS: $PRETTY_NAME"
    
    case $OS in
        ubuntu)
            PACKAGE_MANAGER="apt"
            if [[ "$OS_VERSION" != "24.04" ]]; then
                print_error "Only Ubuntu 24.04 is supported by this script"
                print_info "Detected: Ubuntu $OS_VERSION"
                exit 1
            fi
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            print_info "This script only supports Ubuntu 24.04"
            exit 1
            ;;
    esac
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_internet() {
    print_info "Checking internet connectivity..."
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No internet connection available"
        exit 1
    fi
    print_success "Internet connectivity verified"
}

#
# Package Management Functions
#

install_dependencies_ubuntu() {
    print_step "Installing dependencies for Ubuntu $OS_VERSION"
    
    apt update
    
    # Build dependencies
    apt install -y \
        gcc make libtool autoconf automake g++ \
        libhwloc-dev libx11-dev libxt-dev libedit-dev \
        libical-dev ncurses-dev perl python3-dev tcl-dev \
        tk-dev swig libexpat-dev libssl-dev libxext-dev \
        libxft-dev libcjson-dev pkg-config git wget \
        build-essential
    
    # Runtime dependencies
    apt install -y \
        expat libedit2 python3 sendmail-bin \
        tcl tk libical3 hwloc-nox libcjson1
    
    # PostgreSQL dependencies (if accounting enabled)
    if [[ "$ENABLE_ACCOUNTING" == "true" ]]; then
        apt install -y postgresql-server-dev-all
        if [[ "$INSTALL_POSTGRES" == "true" ]]; then
            apt install -y postgresql postgresql-contrib
        fi
    fi
}

install_dependencies_rhel() {
    print_step "Installing dependencies for RHEL/CentOS/Rocky $OS_VERSION"
    
    # Enable EPEL repository
    if [[ "$OS_VERSION_MAJOR" == "7" ]]; then
        $PACKAGE_MANAGER install -y epel-release
    elif [[ "$OS_VERSION_MAJOR" == "8" ]] || [[ "$OS_VERSION_MAJOR" == "9" ]]; then
        $PACKAGE_MANAGER install -y epel-release
        if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
            dnf config-manager --set-enabled powertools 2>/dev/null || \
            dnf config-manager --set-enabled PowerTools 2>/dev/null || \
            dnf config-manager --set-enabled crb 2>/dev/null || true
        fi
    fi
    
    # Build dependencies
    $PACKAGE_MANAGER groupinstall -y "Development Tools"
    $PACKAGE_MANAGER install -y \
        gcc make libtool autoconf automake \
        hwloc-devel libX11-devel libXt-devel libedit-devel \
        libical-devel ncurses-devel perl python3-devel \
        tcl-devel tk-devel swig expat-devel openssl-devel \
        libXext-devel libXft-devel libcjson-devel git wget
    
    # PostgreSQL dependencies (if accounting enabled)
    if [[ "$ENABLE_ACCOUNTING" == "true" ]]; then
        $PACKAGE_MANAGER install -y postgresql-devel
        if [[ "$INSTALL_POSTGRES" == "true" ]]; then
            $PACKAGE_MANAGER install -y postgresql-server postgresql-contrib
        fi
    fi
}

#
# OpenPBS Installation Functions
#

download_openpbs() {
    print_step "Downloading OpenPBS source code"
    
    cd /tmp
    rm -rf openpbs-* || true
    
    if [[ "$PBS_VERSION" == "master" ]]; then
        print_info "Downloading latest development version..."
        wget -O openpbs-master.tar.gz \
            "https://github.com/openpbs/openpbs/archive/refs/heads/master.tar.gz"
        tar -zxf openpbs-master.tar.gz
        cd openpbs-master
    else
        print_info "Downloading OpenPBS version $PBS_VERSION..."
        wget -O openpbs-${PBS_VERSION}.tar.gz \
            "https://github.com/openpbs/openpbs/archive/refs/tags/v${PBS_VERSION}.tar.gz"
        tar -zxf openpbs-${PBS_VERSION}.tar.gz
        cd openpbs-${PBS_VERSION}
    fi
    
    print_success "Source code downloaded and extracted"
}

compile_openpbs() {
    print_step "Compiling OpenPBS (this may take 15-30 minutes)"
    
    # Generate configure script
    print_info "Running autogen.sh..."
    ./autogen.sh
    
    # Configure build
    print_info "Configuring build..."
    local configure_args="--prefix=$PBS_PREFIX"
    
    if [[ "$ENABLE_ACCOUNTING" == "true" ]]; then
        configure_args+=" --enable-ptl --with-database-user=postgres"
    fi
    
    ./configure $configure_args
    
    # Compile
    print_info "Compiling (using $(nproc) cores)..."
    make -j$(nproc)
    
    # Install
    print_info "Installing OpenPBS..."
    make install
    
    print_success "OpenPBS compiled and installed successfully"
}

configure_postgresql() {
    if [[ "$ENABLE_ACCOUNTING" != "true" ]]; then
        return
    fi
    
    print_step "Configuring PostgreSQL for PBS accounting"
    
    if [[ "$INSTALL_POSTGRES" == "true" ]]; then
        case $OS in
            ubuntu)
                systemctl start postgresql
                systemctl enable postgresql
                ;;
            centos|rhel|rocky|almalinux)
                if [[ "$OS_VERSION_MAJOR" == "7" ]]; then
                    postgresql-setup initdb
                fi
                systemctl start postgresql
                systemctl enable postgresql
                ;;
        esac
    fi
    
    # Configure PBS database
    if [[ -n "$POSTGRES_PASSWORD" ]]; then
        sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"
    fi
    
    sudo -u postgres createdb pbs_datastore 2>/dev/null || true
    sudo -u postgres createuser pbs 2>/dev/null || true
    
    print_success "PostgreSQL configured for PBS accounting"
}

post_install_setup() {
    print_step "Running post-installation setup"
    
    # Run PBS post-install script
    $PBS_PREFIX/libexec/pbs_postinstall
    
    # Set proper permissions
    chmod 4755 $PBS_PREFIX/sbin/pbs_iff $PBS_PREFIX/sbin/pbs_rcp
    
    # Add PBS to PATH
    cat > /etc/profile.d/pbs.sh << EOF
export PATH=$PBS_PREFIX/bin:$PBS_PREFIX/sbin:\$PATH
export PBS_EXEC=$PBS_PREFIX
export PBS_HOME=$PBS_HOME
EOF
    
    source /etc/profile.d/pbs.sh
    
    print_success "Post-installation setup completed"
}

#
# Configuration Functions
#

configure_server_node() {
    print_step "Configuring PBS server node"
    
    cat > /etc/pbs.conf << EOF
PBS_SERVER=$SERVER_HOSTNAME
PBS_START_SERVER=1
PBS_START_SCHED=1
PBS_START_COMM=1
PBS_START_MOM=0
PBS_EXEC=$PBS_PREFIX
PBS_HOME=$PBS_HOME
PBS_CORE_LIMIT=unlimited
PBS_SCP=/usr/bin/scp
EOF
    
    # Create default queue
    print_info "Creating default queue..."
    systemctl start pbs
    sleep 5
    
    qmgr -c "create queue workq"
    qmgr -c "set queue workq queue_type = Execution"
    qmgr -c "set queue workq enabled = True"
    qmgr -c "set queue workq started = True"
    qmgr -c "set queue workq resources_max.walltime = 24:00:00"
    qmgr -c "set server default_queue = workq"
    qmgr -c "set server scheduling = True"
    
    print_success "PBS server configured successfully"
}

configure_compute_node() {
    print_step "Configuring PBS compute node"
    
    if [[ -z "$SERVER_HOSTNAME" ]]; then
        print_error "Server hostname must be specified for compute nodes"
        exit 1
    fi
    
    cat > /etc/pbs.conf << EOF
PBS_SERVER=$SERVER_HOSTNAME
PBS_START_SERVER=0
PBS_START_SCHED=0
PBS_START_COMM=0
PBS_START_MOM=1
PBS_EXEC=$PBS_PREFIX
PBS_HOME=$PBS_HOME
PBS_CORE_LIMIT=unlimited
PBS_SCP=/usr/bin/scp
EOF
    
    # Configure MOM
    mkdir -p $PBS_HOME/mom_priv
    cat > $PBS_HOME/mom_priv/config << EOF
\$clienthost $SERVER_HOSTNAME
\$restrict_user_maxsysid 999
EOF
    
    print_success "PBS compute node configured successfully"
}

#
# Interactive Setup Functions
#

interactive_setup() {
    print_header
    echo "Welcome to the OpenPBS Installation Wizard"
    echo "This script will guide you through the installation process."
    echo ""
    
    # Node type selection
    echo "Select the type of PBS node to install:"
    echo "1) Server node (PBS server + scheduler)"
    echo "2) Compute node (PBS MOM)"
    echo "3) Both (single-node setup)"
    echo ""
    read -p "Enter your choice [1-3]: " choice
    
    case $choice in
        1) NODE_TYPE="server" ;;
        2) NODE_TYPE="compute" ;;
        3) NODE_TYPE="both" ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
    
    # Server hostname
    if [[ "$NODE_TYPE" == "compute" ]] || [[ "$NODE_TYPE" == "both" ]]; then
        read -p "Enter PBS server hostname [$(hostname -f)]: " input_hostname
        SERVER_HOSTNAME="${input_hostname:-$(hostname -f)}"
    else
        SERVER_HOSTNAME=$(hostname -f)
    fi
    
    # Cluster name
    read -p "Enter cluster name [$DEFAULT_CLUSTER_NAME]: " input_cluster
    CLUSTER_NAME="${input_cluster:-$DEFAULT_CLUSTER_NAME}"
    
    # Accounting support
    read -p "Enable PBS accounting with PostgreSQL? [y/N]: " accounting_choice
    if [[ "$accounting_choice" =~ ^[Yy]$ ]]; then
        ENABLE_ACCOUNTING=true
        
        # Check if PostgreSQL is installed
        if ! command -v psql &> /dev/null; then
            read -p "PostgreSQL not found. Install it? [Y/n]: " postgres_install
            if [[ ! "$postgres_install" =~ ^[Nn]$ ]]; then
                INSTALL_POSTGRES=true
            fi
        fi
        
        if [[ "$INSTALL_POSTGRES" == "true" ]] || command -v psql &> /dev/null; then
            read -s -p "Enter PostgreSQL password (leave empty for no password): " POSTGRES_PASSWORD
            echo ""
        fi
    fi
    
    # Confirmation
    echo ""
    echo "Configuration Summary:"
    echo "- Node Type: $NODE_TYPE"
    echo "- Server Hostname: $SERVER_HOSTNAME"
    echo "- Cluster Name: $CLUSTER_NAME"
    echo "- PBS Version: $PBS_VERSION"
    echo "- Installation Prefix: $PBS_PREFIX"
    echo "- Accounting: $ENABLE_ACCOUNTING"
    echo ""
    read -p "Proceed with installation? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
}

#
# Validation Functions
#

check_existing_installation() {
    if [[ -d "$PBS_PREFIX" ]] && [[ "$FORCE_REINSTALL" != "true" ]]; then
        print_warning "OpenPBS installation detected at $PBS_PREFIX"
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            read -p "Continue with reinstallation? [y/N]: " reinstall
            if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
                exit 0
            fi
        else
            print_error "Use --force-reinstall to overwrite existing installation"
            exit 1
        fi
    fi
}

validate_configuration() {
    if [[ "$NODE_TYPE" == "compute" ]] && [[ -z "$SERVER_HOSTNAME" ]]; then
        print_error "Server hostname is required for compute nodes"
        exit 1
    fi
    
    if [[ "$ENABLE_ACCOUNTING" == "true" ]] && [[ "$NODE_TYPE" != "server" ]] && [[ "$NODE_TYPE" != "both" ]]; then
        print_warning "Accounting is only configured on server nodes"
        ENABLE_ACCOUNTING=false
    fi
}

#
# Installation Functions
#

install_dependencies() {
    print_step "Installing system dependencies"
    
    case $OS in
        ubuntu)
            install_dependencies_ubuntu
            ;;
        centos|rhel|rocky|almalinux)
            install_dependencies_rhel
            ;;
    esac
    
    print_success "Dependencies installed successfully"
}

install_openpbs() {
    print_step "Installing OpenPBS"
    
    # Stop existing PBS services
    systemctl stop pbs 2>/dev/null || true
    
    download_openpbs
    compile_openpbs
    
    if [[ "$ENABLE_ACCOUNTING" == "true" ]]; then
        configure_postgresql
    fi
    
    post_install_setup
}

configure_services() {
    print_step "Configuring PBS services"
    
    case $NODE_TYPE in
        server)
            configure_server_node
            ;;
        compute)
            configure_compute_node
            ;;
        both)
            SERVER_HOSTNAME=$(hostname -f)
            configure_server_node
            ;;
    esac
    
    # Enable and start services
    systemctl enable pbs
    systemctl start pbs
    
    print_success "PBS services configured and started"
}

#
# Testing Functions
#

run_tests() {
    print_step "Running installation tests"
    
    # Wait for services to start
    sleep 10
    
    # Test server
    if [[ "$NODE_TYPE" == "server" ]] || [[ "$NODE_TYPE" == "both" ]]; then
        print_info "Testing PBS server..."
        if qstat -B &> /dev/null; then
            print_success "PBS server is running"
        else
            print_warning "PBS server test failed"
        fi
    fi
    
    # Test compute nodes
    if [[ "$NODE_TYPE" == "compute" ]] || [[ "$NODE_TYPE" == "both" ]]; then
        print_info "Testing PBS MOM..."
        if pgrep pbs_mom &> /dev/null; then
            print_success "PBS MOM is running"
        else
            print_warning "PBS MOM test failed"
        fi
    fi
    
    # Create test job
    if [[ "$NODE_TYPE" == "server" ]] || [[ "$NODE_TYPE" == "both" ]]; then
        print_info "Submitting test job..."
        cat > /tmp/test_job.pbs << 'EOF'
#!/bin/bash
#PBS -N test_job
#PBS -l select=1:ncpus=1
#PBS -l walltime=00:01:00
#PBS -j oe

echo "Test job running on: $(hostname)"
echo "Job ID: $PBS_JOBID"
echo "Date: $(date)"
EOF
        
        if job_id=$(qsub /tmp/test_job.pbs 2>/dev/null); then
            print_success "Test job submitted: $job_id"
        else
            print_warning "Test job submission failed"
        fi
    fi
}

#
# Main Installation Function
#

main() {
    print_header
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-type=*)
                NODE_TYPE="${1#*=}"
                INTERACTIVE_MODE=false
                ;;
            --server-hostname=*)
                SERVER_HOSTNAME="${1#*=}"
                ;;
            --cluster-name=*)
                CLUSTER_NAME="${1#*=}"
                ;;
            --enable-accounting)
                ENABLE_ACCOUNTING=true
                ;;
            --postgres-password=*)
                POSTGRES_PASSWORD="${1#*=}"
                ;;
            --install-postgres)
                INSTALL_POSTGRES=true
                ;;
            --force-reinstall)
                FORCE_REINSTALL=true
                ;;
            --without-interaction)
                INTERACTIVE_MODE=false
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    
    # Validation
    check_root
    check_internet
    detect_os
    check_existing_installation
    
    # Interactive setup if needed
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        interactive_setup
    fi
    
    validate_configuration
    
    # Installation process
    print_info "Starting OpenPBS installation..."
    print_info "Log file: $LOG_FILE"
    
    install_dependencies
    install_openpbs
    configure_services
    run_tests
    
    # Installation summary
    print_step "Installation Summary"
    echo ""
    print_success "OpenPBS installation completed successfully!"
    echo ""
    echo "Configuration Details:"
    echo "- Node Type: $NODE_TYPE"
    echo "- Server: $SERVER_HOSTNAME"
    echo "- Cluster: $CLUSTER_NAME"
    echo "- Installation Path: $PBS_PREFIX"
    echo "- Accounting: $ENABLE_ACCOUNTING"
    echo "- Log File: $LOG_FILE"
    echo ""
    
    if [[ "$NODE_TYPE" == "server" ]] || [[ "$NODE_TYPE" == "both" ]]; then
        echo "Server Commands:"
        echo "- Check status: qstat -B"
        echo "- List nodes: pbsnodes -a"
        echo "- Submit job: qsub script.pbs"
        echo ""
    fi
    
    if [[ "$NODE_TYPE" == "compute" ]]; then
        echo "To add this compute node to the server, run on the server:"
        echo "qmgr -c \"create node $(hostname -f)\""
        echo ""
    fi
    
    echo "For troubleshooting, check: $LOG_FILE"
    echo "Documentation: https://openpbs.org"
}

#
# Error handling and cleanup
#

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Installation failed with exit code $exit_code"
        print_info "Check log file: $LOG_FILE"
    fi
    
    # Clean up temporary files
    rm -f /tmp/openpbs-*.tar.gz 2>/dev/null || true
}

trap cleanup EXIT

# Start main execution
main "$@"