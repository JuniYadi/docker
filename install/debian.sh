#!/bin/bash
# Docker Installation
# Tested Debian 10
# Updated = 30/11/2019
# Juni Yadi <me@juniyadi.id>

# Deleted Old Version
apt-get remove docker docker-engine docker.io containerd runc

# Update System
apt-get update

# Install Require Package Docker
apt-get install \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg2 \
        software-properties-common -y

# Added Docker Official GPG
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
apt-key fingerprint 0EBFCD88

# Added Docker Repository
add-apt-repository \
        "deb [arch=amd64] https://download.docker.com/linux/debian \
        $(lsb_release -cs) \
        stable"

# Update System
apt-get update

# Install Docker
apt-get install \
        docker-ce \
        docker-ce-cli \
        containerd.io -y

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.25.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Portainer For Managed Docker From GUI Sites
if [ "$1" != "-n" ]; then
    docker run -d -p 9000:9000 -p 8000:8000 --name portainer --restart always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer

    echo "Docker Portainer Has Been Install"
    echo "Access with http://127.0.0.1:9000"

fi
