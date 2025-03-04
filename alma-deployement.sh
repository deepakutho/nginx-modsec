#!/bin/bash

# Exit if any command fails
set -e


# Install Nginx
echo "Installing Nginx..."

sudo dnf install -y nginx curl wget git
sudo dnf install epel-release -y
yum install goaccess -y
sudo dnf install mod_security
sudo dnf install nginx-mod-modsecurity.x86_64
# Start and enable Nginx
echo "Starting and enabling Nginx..."
sudo systemctl start nginx
sudo systemctl enable nginx
sudo dnf install -y gcc pcre-devel zlib-devel make libtool libxml2-devel libxslt-devel

# Install dependencies for ModSecurity
echo "Installing ModSecurity dependencies..."
sudo dnf install -y gcc-c++ make automake libtool pcre-devel zlib-devel curl-devel git

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
sudo dnf install -y nginx-mod-stream nginx-mod-http-perl nginx-filesystem


# Download GeoLite2 Country database
echo "Downloading MaxMind GeoLite2 Country database..."
wget https://cdn.jsdelivr.net/npm/geolite2-country/GeoLite2-Country.mmdb.gz
gunzip GeoLite2-Country.mmdb.gz
sudo mkdir -p /usr/share/GeoIP
sudo mv GeoLite2-Country.mmdb /usr/share/GeoIP/

# Configure ModSecurity with Nginx
echo "Configuring ModSecurity with Nginx..."

sudo mkdir -p /etc/nginx/modsec

# Add initial ModSecurity configuration
echo "SecRuleEngine On" | sudo tee /etc/nginx/modsec/main.conf
echo "SecGeoLookupDb /usr/share/GeoIP/GeoLite2-Country.mmdb" | sudo tee -a /etc/nginx/modsec/main.conf
# Allow access from India
echo "SecRule REMOTE_ADDR \"@geoLookup\" \"phase:1,id:12345,t:none,pass,nolog\"" | sudo tee -a /etc/nginx/modsec/main.conf
# Block access from all countries except India (IN)
echo "SecRule GEO:COUNTRY_CODE \"!@streq IN\" \\" | sudo tee -a /etc/nginx/modsec/main.conf
echo "    \"phase:1,id:12346,deny,status:403,msg:'Access from restricted country'\"" | sudo tee -a /etc/nginx/modsec/main.conf
# Modify Nginx configuration to include ModSecurity
#echo "Modifying Nginx configuration..."
#sudo sed -i '/http {/a \ \ load_module modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf
#echo "modsecurity on;" | sudo tee -a /etc/nginx/nginx.conf
#echo "modsecurity_rules_file /etc/nginx/modsec/main.conf;" | sudo tee -a /etc/nginx/nginx.conf
# Create /etc/nginx/proxy_params and add proxy parameters
echo "# /etc/nginx/proxy_params" | sudo tee /etc/nginx/proxy_params
echo "proxy_set_header Host \$host;" | sudo tee -a /etc/nginx/proxy_params
echo "proxy_set_header X-Real-IP \$remote_addr;" | sudo tee -a /etc/nginx/proxy_params
echo "proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" | sudo tee -a /etc/nginx/proxy_params
echo "proxy_set_header X-Forwarded-Proto \$scheme;" | sudo tee -a /etc/nginx/proxy_params
# Configure proxy to Tomcat (assuming Tomcat runs on port 8080)
echo "Configuring Nginx to proxy requests to Tomcat..."
sudo tee -a /etc/nginx/nginx.conf <<EOF
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    include /etc/nginx/conf.d/*.conf;

    # ModSecurity configuration
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsec/main.conf;

    # Default server block (HTTP)
}
EOF

# Restart Nginx to apply changes
echo "Restarting Nginx..."
sudo systemctl restart nginx

# Verify Nginx configuration
echo "Verifying Nginx configuration..."
sudo nginx -t

# Clean up
echo "Cleaning up temporary files..."
cd ~
rm -rf /tmp/ModSecurity
rm -rf /tmp/ModSecurity-nginx
rm -f GeoLite2-Country.mmdb.gz

# Done
echo "Installation and configuration complete! Nginx is now set up with ModSecurity and GeoIP."
