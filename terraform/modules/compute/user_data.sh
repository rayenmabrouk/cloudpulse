#!/bin/bash
set -euo pipefail

# Update system
dnf update -y

# Install Docker
dnf install -y docker
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Create application directory
mkdir -p /opt/cloudpulse

echo "CloudPulse bootstrap complete" | tee /var/log/cloudpulse-init.log
