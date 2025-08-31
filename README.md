# OpenPBS installation script

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![OS Support](https://img.shields.io/badge/OS-Ubuntu%2024.04-green.svg)
![Architecture](https://img.shields.io/badge/arch-x86__64%20|%20arm64-lightgrey.svg)

A comprehensive installation script for OpenPBS (Portable Batch System) that automates the download, compilation, and configuration process across multiple Linux distributions.

## ✨ Features

- **Distribution Support**: Ubuntu 24.04
- **Architecture Support**: x86_64 and arm64
- **Flexible Node Types**: Server, compute, or combined installations
- **Accounting Support**: Optional PostgreSQL integration for job accounting
- **Interactive & Non-Interactive**: Both guided setup and automated deployment
- **Source Compilation**: Always uses latest features from OpenPBS master branch
- **Production Ready**: Includes proper security configurations and service management

## 🚀 Quick Start

### One-Line Installation

```bash
# Download and run installer
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/AhmedMejri1/OpenPBS-installation-script/main/pbs_install.sh)"
```

### Standard Installation

```bash
# Clone repository
git clone https://github.com/AhmedMejri1/OpenPBS-installation-script.git
cd OpenPBS-installation-script

# Make executable
chmod +x pbs_install.sh

# Run installer
sudo ./pbs_install.sh
```

## 📋 Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Server Node** | 2GB RAM, 20GB disk | 4GB RAM, 50GB disk |
| **Compute Node** | 1GB RAM, 10GB disk | 2GB RAM, 20GB disk |
| **Network** | 100 Mbps | 1 Gbps |

### Supported Operating Systems

- **Ubuntu**: 24.04 ✅ (Fully tested)

## 🔧 Usage

### Interactive Installation

```bash
sudo ./pbs_install.sh
```

The script will guide you through:
1. Node type selection (server/compute/both)
2. Cluster configuration
3. Optional accounting setup
4. Service configuration

### Non-Interactive Installation

#### PBS Server Node
```bash
sudo ./pbs_install.sh \
    --node-type=server \
    --cluster-name=mycluster \
    --without-interaction
```

#### PBS Compute Node
```bash
sudo ./pbs_install.sh \
    --node-type=compute \
    --server-hostname=pbsserver \
    --without-interaction
```

#### Server with Accounting
```bash
sudo ./pbs_install.sh \
    --node-type=server \
    --enable-accounting \
    --install-postgres \
    --postgres-password=securepass \
    --without-interaction
```

### Add Compute Nodes

After installing compute nodes, register them with the server:

```bash
# On server node, add each compute node
qmgr -c "create node node01"
qmgr -c "create node node02"

# Set node properties (optional)
qmgr -c "set node node01 resources_available.ncpus = 8"
qmgr -c "set node node01 resources_available.mem = 16gb"
```

## 🛠️ Troubleshooting

### Common Issues

#### Services Won't Start
```bash
# Check service status
systemctl status pbs

# View logs
journalctl -u pbs -f

# Verify configuration
/opt/pbs/sbin/pbs_probe -v
```

#### Nodes Show as Down
```bash
# Clear node state
pbsnodes -c node01

# Restart MOM on compute node
systemctl restart pbs

# Force node online
pbsnodes -r node01
```

#### Jobs Stuck in Queue
```bash
# Check scheduler logs
tail -f /var/spool/pbs/sched_logs/$(date +%Y%m%d)

# Verify node resources
pbsnodes -a | grep -E "(state|resources)"

# Check queue configuration
qstat -Qf workq
```

### Log Locations

- **Server**: `/var/spool/pbs/server_logs/`
- **Scheduler**: `/var/spool/pbs/sched_logs/`
- **MOM**: `/var/spool/pbs/mom_logs/`
- **Communication**: `/var/spool/pbs/comm_logs/`

## 🔧 Configuration Management

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PBS_VERSION` | OpenPBS version to install | `master` |
| `PBS_PREFIX` | Installation directory | `/opt/pbs` |
| `PBS_HOME` | PBS working directory | `/var/spool/pbs` |

### Configuration Files

- **Main Config**: `/etc/pbs.conf`
- **Server Config**: `/var/spool/pbs/server_priv/`
- **MOM Config**: `/var/spool/pbs/mom_priv/config`
- **Scheduler Config**: `/var/spool/pbs/sched_priv/`

## 📊 Advanced Features

### Resource Management

```bash
# Create custom resources
qmgr -c "create resource gpu type=long flag=nh"
qmgr -c "set node node01 resources_available.gpu = 2"

# Configure node groups
qmgr -c "create node_group high_mem"
qmgr -c "set node_group high_mem nodes = node01,node02"
```

### Queue Configuration

```bash
# Create specialized queues
qmgr -c "create queue gpu_queue"
qmgr -c "set queue gpu_queue queue_type = Execution"
qmgr -c "set queue gpu_queue enabled = True"
qmgr -c "set queue gpu_queue started = True"
qmgr -c "set queue gpu_queue resources_min.gpu = 1"
```

### Job Arrays and Dependencies

```bash
# Submit job array
qsub -J 1-10 array_job.pbs

# Job dependencies
job1=$(qsub first_job.pbs)
qsub -W depend=afterok:$job1 second_job.pbs
```

## 🔒 Security Considerations

### Firewall Configuration

```bash
# Ubuntu/Debian
ufw allow from 192.168.0.0/16 to any port 15001:15009

# RHEL/CentOS
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='192.168.0.0/16' port protocol='tcp' port='15001-15009' accept"
firewall-cmd --reload
```

### User Access Control

```bash
# Create PBS operators group
qmgr -c "set server operators = root@pbsserver,admin@pbsserver"

# Set user access controls
qmgr -c "set server acl_roots = root@*"
qmgr -c "set server acl_users = *@*"
```

## 📈 Performance Tuning

### Server Optimization

```bash
# Adjust scheduler parameters
qmgr -c "set server scheduler_iteration = 300"
qmgr -c "set server backfill = true"
qmgr -c "set server backfill_prime = true"

# Memory and CPU limits
qmgr -c "set server default_chunk.mem = 1gb"
qmgr -c "set server default_chunk.ncpus = 1"
```

### System Tuning

```bash
# Increase file limits (add to /etc/security/limits.conf)
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Kernel parameters (add to /etc/sysctl.conf)
echo "net.core.rmem_max = 268435456" >> /etc/sysctl.conf
echo "net.core.wmem_max = 268435456" >> /etc/sysctl.conf
sysctl -p
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup

```bash
git clone https://github.com/AhmedMejri1/OpenPBS-installation-script.git
cd OpenPBS-installation-script

# Test in virtual environment
vagrant up  # See Vagrantfile for test environments
```

### Testing

```bash
# Run tests
./tests/run_tests.sh

# Test specific OS
./tests/test_ubuntu.sh
./tests/test_rhel.sh
```

## 📚 Documentation

- [OpenPBS Official Documentation](https://openpbs.org)
- [PBS Professional Administrator Guide](https://help.altair.com/2023.1.0/PBS%20Professional/PBSAdminGuide2023.1.pdf)
- [Installation Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [Advanced Configuration Examples](docs/ADVANCED_CONFIG.md)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenPBS Community](https://github.com/openpbs/openpbs) for the excellent workload manager
- [NISP GmbH](https://github.com/NISP-GmbH/SLURM) for inspiration from their SLURM installer
- Contributors and testers who helped improve this installer

## 🐛 Bug Reports

Please report issues using our [GitHub Issues](https://github.com/AhmedMejri1/OpenPBS-installation-script/issues) with:
- Operating system and version
- PBS version being installed
- Full error logs
- Installation command used

## 🔄 Changelog

### v1.0.0 (2025-08-31)
- Initial release
- Support for Ubuntu 24.04
- Interactive and non-interactive installation modes
- PostgreSQL accounting integration
- Comprehensive troubleshooting and testing

---

**Star ⭐ this repository if it helped you!**vanced Options

```bash
# Install specific version
export PBS_VERSION=v23.06.06
sudo ./pbs_install.sh --node-type=server

# Custom installation path
export PBS_PREFIX=/usr/local/pbs
sudo ./pbs_install.sh --node-type=server

# Force reinstallation
sudo ./pbs_install.sh --force-reinstall --node-type=server
```

## 📝 Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--node-type=TYPE` | Node type: server, compute, or both | `--node-type=server` |
| `--server-hostname=HOST` | PBS server hostname | `--server-hostname=pbsmaster` |
| `--cluster-name=NAME` | Cluster identifier | `--cluster-name=research-cluster` |
| `--enable-accounting` | Enable PostgreSQL accounting | `--enable-accounting` |
| `--postgres-password=PASS` | PostgreSQL password | `--postgres-password=mypass` |
| `--install-postgres` | Install PostgreSQL server | `--install-postgres` |
| `--force-reinstall` | Overwrite existing installation | `--force-reinstall` |
| `--without-interaction` | Non-interactive mode | `--without-interaction` |

## 🏗️ Architecture Examples

### Single-Node Setup (Development/Testing)
```bash
sudo ./pbs_install.sh --node-type=both --cluster-name=dev-cluster
```

### Multi-Node Cluster
```bash
# On server node (pbsmaster)
sudo ./pbs_install.sh --node-type=server --cluster-name=prod-cluster

# On compute node 1 (node01)
sudo ./pbs_install.sh --node-type=compute --server-hostname=pbsmaster

# On compute node 2 (node02)  
sudo ./pbs_install.sh --node-type=compute --server-hostname=pbsmaster
```

### High-Availability Setup
```bash
# Primary server with accounting
sudo ./pbs_install.sh \
    --node-type=server \
    --cluster-name=ha-cluster \
    --enable-accounting \
    --install-postgres \
    --postgres-password=strongpassword
```

## 🔍 Post-Installation

### Verify Installation

```bash
# Check PBS server status
qstat -B

# List compute nodes
pbsnodes -a

# View queues
qstat -Q
```

### Submit Test Job

```bash
# Create test script
cat > test_job.pbs << EOF
#!/bin/bash
#PBS -N test_job
#PBS -l select=1:ncpus=1
#PBS -l walltime=00:05:00
#PBS -j oe

hostname
date
echo "PBS test job completed successfully"
EOF

# Submit job
qsub test_job.pbs

# Monitor job
qstat
```
