# AWS Tools for Rust Course

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange.svg)](https://ubuntu.com/)
[![AWS](https://img.shields.io/badge/AWS-CLI%20v2-FF9900.svg)](https://aws.amazon.com/cli/)

A collection of bash scripts to quickly provision AWS infrastructure for Rust development courses. Create VPCs, VPN connections, EFS file systems, Lambda functions, S3 buckets, and more.

## 🎯 Overview

These tools help you:
- Create a **Client VPN** to securely connect to AWS private resources
- Mount **EFS** (Elastic File System) to your local machine via NFS
- Manage AWS resources for Rust Lambda functions and S3 buckets
- Enumerate and cleanup all created resources

## 📋 Prerequisites

- **Ubuntu 24.04** (tested)
- **AWS CLI v2** configured with admin credentials
- **Git** and **OpenSSL**

```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure

export AWS_PROFILE=your_profile_name
export AWS_REGION="xx-xxx-1" # your region. e.g. us-west-1.

