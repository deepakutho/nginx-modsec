#!/bin/bash

# Exit if any command fails
set -e

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install Nginx and other dependencies
echo "Installing Nginx and dependencies..."
sudo apt-get install -y nginx curl wget git
sudo apt-get install -y automake autoconf libtool
sudo apt-get install -y libnginx-mod-http-geoip libnginx-mod-http-headers-more-filter libnginx-mod-http-ndk libnginx-mod-http-lua libnginx-mod-http-echo
sudo apt-get install -y build-essential
sudo apt-get install -y libpcre3-dev

# Install GoAccess
echo "Installing GoAccess..."
sudo apt-get install -y goaccess

# Install ModSecurity dependencies
echo "Installing ModSecurity dependencies..."
sudo apt-get install -y gcc make automake libtool pcre2-utils zlib1g-dev libcurl4-openssl-dev libxml2-dev libxslt1-dev

# Clone and build ModSecurity
echo "Cloning and building ModSecurity..."
cd /tmp
git clone --depth 1 -b v3.0.8 https://github.com/SpiderLabs/ModSecurity.git
cd ModSecurity
./build.sh
git submodule init && git submodule update
./configure
make
sudo make install

# Install ModSecurity Nginx Connector
echo "Installing ModSecurity Nginx connector..."
cd /tmp
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

# Install Nginx development tools
echo "Installing Nginx development tools..."
sudo apt-get install -y libnginx-mod-http-headers-more-filter libnginx-mod-http-ndk libnginx-mod-http-lua libnginx-mod-http-echo
sudo apt-get install -y libnginx-mod-http-modsecurity

# Download GeoLite2 Country database
echo "Downloading MaxMind GeoLite2 Country database..."
wget https://cdn.jsdelivr.net/npm/geolite2-country/GeoLite2-Country.mmdb.gz
gunzip GeoLite2-Country.mmdb.gz
sudo mkdir -p /usr/share/GeoIP
sudo mv GeoLite2-Country.mmdb /usr/share/GeoIP/

# Configure ModSecurity with Nginx
echo "Configuring ModSecurity with Nginx..."
sudo mkdir -p /etc/nginx/modsec
cd /tmp
sudo git clone --depth 1 https://github.com/deepakutho/nginx-modsec.git
mv /etc/nginx /media/.
cd nginx-modsec
mv debian-nginx /etc/nginx
mv letsencrypt /etc/letsencrypt	
# Verify Nginx configuration
echo "Verifying Nginx configuration..."
sudo nginx -t
# Restart Nginx to apply changes
echo "Restarting Nginx..."
sudo systemctl restart nginx



# Clean up
echo "Cleaning up temporary files..."
cd ~
rm -rf /tmp/ModSecurity
rm -rf /tmp/ModSecurity-nginx
rm -f GeoLite2-Country.mmdb.gz

# Done
echo "Installation and configuration complete! Nginx is now set up with ModSecurity and GeoIP."