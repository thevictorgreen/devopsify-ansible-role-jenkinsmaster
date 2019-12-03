#!/bin/bash

# LOG OUTPUT TO A FILE
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/root/.jenkins_automate/log.out 2>&1

if [[ ! -f "/root/.jenkins_automate/init.cfg" ]]
then
  # Install unzip
  apt-get install -y unzip
  # Install Java
  apt-get install -y default-jdk
  # Install Ant
  wget -q --show-progress --https-only --timestamping http://apache.mirrors.tds.net//ant/binaries/apache-ant-1.10.6-bin.zip
  unzip $PWD/apache-ant-1.10.6-bin.zip
  rm -rf $PWD/apache-ant-1.10.6-bin.zip
  mv $PWD/apache-ant-1.10.6 /usr/share/
  # Install Maven
  wget -q --show-progress --https-only --timestamping http://mirror.metrocast.net/apache/maven/maven-3/3.6.1/binaries/apache-maven-3.6.1-bin.zip
  unzip apache-maven-3.6.1-bin.zip
  rm -rf $PWD/apache-maven-3.6.1-bin.zip
  mv $PWD/apache-maven-3.6.1 /usr/share
  # Set JAVA_HOME Environment Variable:
  # Set ANT_HOME environment variable:
  # Add ANT to PATH environment variable:
  cat <<EOF > /etc/environment
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/share/apache-ant-1.10.6/bin:/usr/share/apache-maven-3.6.1/bin"
export JAVA_HOME=/usr/lib/jvm/default-java
export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
export ANT_HOME=/usr/share/apache-ant-1.10.6
EOF
  source /etc/environment
  # INSTALL NGINX
  apt-get install -y nginx
  # INSTALL CERTBOT
  add-apt-repository ppa:certbot/certbot
  apt-get update -y
  apt-get install -y python-certbot-nginx
  # INSTALL JENKINS
  wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
  echo deb http://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list
  apt-get update -y
  apt-get install jenkins -y
  # Add jenkins user to sudoers file
  echo "jenkins ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers
  # INSTALL DOCKER
  apt-get install -y docker.io
  # INSTALL GIT
  apt-get install -y git
  # INSTALL ANSIBLE
  apt-add-repository ppa:ansible/ansible
  apt-get update -y
  apt-get install -y ansible
  # Make Jenkins only listen on localhost
  systemctl stop jenkins
  head -n -2 /etc/default/jenkins >> jenkins
  echo JENKINS_ARGS=$'"--webroot=/var/cache/$NAME/war --httpPort=$HTTP_PORT --httpListenAddress=127.0.0.1"' >> jenkins
  mv $PWD/jenkins /etc/default/jenkins
  # Configure Nginx
  systemctl stop nginx
  # CREATE SELF SIGNED CERTIFICATE FOR NGINX
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -subj "/C=US/ST=Washington/L=DC/O=Deloitte/OU=CYARC/CN=10.224.0.43" -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt
  # CREATE A STRONG DHG
  openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
  # Create a Configuration Snippet Pointing to the SSL Key and Certificate
  cat <<EOF > /etc/nginx/snippets/self-signed.conf
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF
# Create a Configuration Snippet with Strong Encryption Settings
cat <<EOF > /etc/nginx/snippets/ssl-params.conf
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_prefer_server_ciphers on;
ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
ssl_ecdh_curve secp384r1;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
#ssl_stapling on;
#ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
# Disable preloading HSTS for now.  You can use the commented out header line that includes
# the "preload" directive if you understand the implications.
#add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;

ssl_dhparam /etc/ssl/certs/dhparam.pem;
EOF
#Nginx Reverse SSL Proxy Configuration
cat <<EOF > /etc/nginx/sites-available/default
# Default server configuration
#
server {
     listen 80;
     server_name $(hostname);
     return 301 https://$host$request_uri;
}

server {
        listen 443 ssl http2 default_server;
        include snippets/self-signed.conf;
        include snippets/ssl-params.conf;
        access_log /var/log/nginx/jenkins.access.log;
        error_log  /var/log/nginx/jenkins.error.log;

       root /var/www/html;

        # Add index.php to the list if you are using PHP
       index index.html index.htm index.nginx-debian.html;


        location / {
                include /etc/nginx/proxy_params;
                proxy_pass http://localhost:8080;
                proxy_read_timeout 90s;
                proxy_redirect http://localhost:8080 https://$(hostname);
        }

}
EOF
  # CHECK NGINX CONFIGURATION
  nginx -t
  # START SERVICES
  systemctl start jenkins
  systemctl start nginx
  #Show Jenkins Password
  echo "Jenkins Initial Password:"
  cat /var/lib/jenkins/secrets/initialAdminPassword
  # Idempotentcy
  touch /root/.jenkins_automate/init.cfg
fi
