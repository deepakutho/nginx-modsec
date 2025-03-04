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
cd /etc/nginx/modsec
sudo git clone --depth 1 https://github.com/coreruleset/coreruleset.git
sudo mv coreruleset crs
sudo cp crs/crs-setup.conf.example crs/crs-setup.conf

# Add initial ModSecurity configuration
echo "SecRuleEngine On" | sudo tee /etc/nginx/modsec/main.conf
echo "SecGeoLookupDb /usr/share/GeoIP/GeoLite2-Country.mmdb" | sudo tee -a /etc/nginx/modsec/main.conf
echo 'Include /etc/nginx/modsec/crs/rules/*.conf' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'Include /etc/nginx/modsec/modsecurity.conf' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'Include /etc/nginx/modsec/crs/crs-setup.conf' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'SecAuditEngine RelevantOnly' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'SecAuditLogParts ABIJDEFHZ' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'SecAuditLogType Serial' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'SecAuditLog /var/log/nginx/modsec_audit.log' | sudo tee -a /etc/nginx/modsec/main.conf
echo 'SecAuditLogFormat JSON' | sudo tee -a /etc/nginx/modsec/main.conf
# Allow access from India
echo "SecRule REMOTE_ADDR \"@geoLookup\" \"phase:1,id:12345,t:none,pass,nolog\"" | sudo tee -a /etc/nginx/modsec/main.conf
# Block access from all countries except India (IN)
echo "SecRule GEO:COUNTRY_CODE \"!@streq IN\" \\" | sudo tee -a /etc/nginx/modsec/main.conf
echo "    \"phase:1,id:12346,deny,status:403,msg:'Access from restricted country'\"" | sudo tee -a /etc/nginx/modsec/main.conf

# Create /etc/nginx/proxy_params and add proxy parameters
echo "# /etc/nginx/proxy_params" | sudo tee /etc/nginx/proxy_params
echo "proxy_set_header Host \$host;" | sudo tee -a /etc/nginx/proxy_params
echo "proxy_set_header X-Real-IP \$remote_addr;" | sudo tee -a /etc/nginx/proxy_params
echo "proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" | sudo tee -a /etc/nginx/proxy_params
echo "proxy_set_header X-Forwarded-Proto \$scheme;" | sudo tee -a /etc/nginx/proxy_params

# Configure proxy to Tomcat (assuming Tomcat runs on port 8080)
echo "Configuring Nginx to proxy requests to Tomcat..."
sudo mv /etc/nginx/nginx.conf /media/nginx.conf
sudo tee -a /etc/nginx/nginx.conf <<EOF
load_module modules/ngx_http_modsecurity_module.so;
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/
user www-data;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

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

sudo tee -a /etc/nginx/conf.d/reverse-proxy.conf <<EOF
server {
    listen 80;
    server_name wecloud.remotedevadmin.in;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name wecloud.remotedevadmin.in;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;


    ssl_certificate /etc/letsencrypt/live/wecloud.remotedevadmin.in/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wecloud.remotedevadmin.in/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

    #ssl_protocols TLSv1.2 TLSv1.3;
    #ssl_ciphers HIGH:!aNULL:!MD5;


    location / {
        proxy_pass http://157.20.214.104;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#        proxy_redirect http:// https://;
    }
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