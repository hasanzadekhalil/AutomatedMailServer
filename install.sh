#!/bin/bash

# Prompt the user for the domain name
read -p "Please enter the domain name (e.g., example.com): " DOMAIN

IP=$(curl -s http://checkip.amazonaws.com)
echo "Record Type: A, @ domain Bind to > $IP 
Record Type: A, mail.$DOMAIN @ Bind to > $IP 
Record Type: MX, @ Bind to > mail.$DOMAIN"
read -p "Please Verify above records, After Verify Click any button for continue..."

# Prompt the user for the admin password
read -sp "Please enter the admin password: " AdminPassword
echo

if ! [ -x "$(command -v curl)" ]; then
    echo "curl is not installed. Installing curl..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update
        sudo apt-get install curl -y
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install curl -y
    else
        echo "Package manager not found. Please install curl manually."
        exit 1
    fi
    echo "curl has been successfully installed."
fi

# Check if Docker is installed
if ! [ -x "$(command -v docker)" ]; then
    echo "Docker is not installed. Downloading and installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "Docker has been successfully installed."
fi

# Check if Docker Compose is installed, if not, install it
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed. Downloading and installing Docker Compose..."
    curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose has been successfully installed."
fi

# Check DNS records before proceeding
echo "Checking DNS records for $DOMAIN..."
DNS_RECORDS=$(dig +short $DOMAIN)
if [ -z "$DNS_RECORDS" ]; then
    echo "No DNS records found for $DOMAIN. Please ensure the DNS is properly configured."
    exit 1
else
    echo "DNS records found:"
    echo "$DNS_RECORDS"
fi

# Create a directory for Mailu
mkdir -p /mailu/{redis,overrides,dkim,data,mail,certs,webmail,filter}

# Create the docker-compose.yml file
cat > /mailu/docker-compose.yml <<EOF
version: '2.2'

services:
  redis:
    image: redis:alpine
    restart: always
    volumes:
      - "/mailu/redis:/data"
    depends_on:
      - resolver
    dns:
      - 192.168.200.254


  # Core services
  front:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}nginx:${MAILU_VERSION:-2.0}
    restart: always
    env_file: mailu.env
    logging:
      driver: journald
      options:
        tag: mailu-front
    ports:
      - "0.0.0.0:80:80"
      - "0.0.0.0:443:443"
#      - "0.0.0.0:25:25"
      - "0.0.0.0:465:465"
      - "0.0.0.0:587:587"
      - "0.0.0.0:110:110"
      - "0.0.0.0:995:995"
      - "0.0.0.0:143:143"
      - "0.0.0.0:993:993"
    networks:
      - default
      - webmail
    volumes:
      - "/mailu/certs:/certs"
      - "/mailu/overrides/nginx:/overrides:ro"
    depends_on:
      - resolver
    dns:
      - 192.168.200.254

  resolver:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}unbound:${MAILU_VERSION:-2.0}
    env_file: mailu.env
    restart: always
    networks:
      default:
        ipv4_address: 192.168.200.254

  admin:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}admin:${MAILU_VERSION:-2.0}
    restart: always
    env_file: mailu.env
    logging:
      driver: journald
      options:
        tag: mailu-admin
    volumes:
      - "/mailu/data:/data"
      - "/mailu/dkim:/dkim"
    depends_on:
      - redis
      - resolver
    dns:
      - 192.168.200.254

  imap:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}dovecot:${MAILU_VERSION:-2.0}
    restart: always
    env_file: mailu.env
    logging:
      driver: journald
      options:
        tag: mailu-imap
    volumes:
      - "/mailu/mail:/mail"
      - "/mailu/overrides/dovecot:/overrides:ro"
    depends_on:
      - front
      - resolver
    dns:
      - 192.168.200.254

  smtp:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}postfix:${MAILU_VERSION:-2.0}
    restart: always
    env_file: mailu.env
        logging:
      driver: journald
      options:
        tag: mailu-smtp
    volumes:
      - "/mailu/mailqueue:/queue"
      - "/mailu/overrides/postfix:/overrides:ro"
    depends_on:
      - front
      - resolver
    dns:
      - 192.168.200.254

  oletools:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}oletools:${MAILU_VERSION:-2.0}
    hostname: oletools
    restart: always
    networks:
      - noinet
    depends_on:
      - resolver
    dns:
      - 192.168.200.254

  antispam:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}rspamd:${MAILU_VERSION:-2.0}
    hostname: antispam
    restart: always
    env_file: mailu.env
    logging:
      driver: journald
      options:
        tag: mailu-antispam
    networks:
      - default
      - noinet
    volumes:
      - "/mailu/filter:/var/lib/rspamd"
      - "/mailu/overrides/rspamd:/overrides:ro"
    depends_on:
      - front
      - redis
      - oletools
      - antivirus
      - resolver
    dns:
      - 192.168.200.254

  # Optional services
  antivirus:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}clamav:${MAILU_VERSION:-2.0}
    restart: always
    env_file: mailu.env
    volumes:
      - "/mailu/filter:/data"
    depends_on:
      - resolver
    dns:
      - 192.168.200.254

  # Webmail
  webmail:
    image: ${DOCKER_ORG:-ghcr.io/mailu}/${DOCKER_PREFIX:-}webmail:${MAILU_VERSION:-2.0}
    restart: always
    env_file: mailu.env
    volumes:
      - "/mailu/webmail:/data"
      - "/mailu/overrides/roundcube:/overrides:ro"
    networks:
      - webmail
    depends_on:
      - front
      
networks:
  default:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 192.168.200.0/24
  webmail:
    driver: bridge
  noinet:
    driver: bridge
    internal: true
EOF

# Create the mailu.env file
cat > /mailu/mailu.env <<EOF

# Mailu main configuration file
#
# This file is autogenerated by the configuration management wizard for compose flavor.
# For a detailed list of configuration variables, see the documentation at
# https://mailu.io

###################################
# Common configuration variables
###################################

# Set to a randomly generated 16 bytes string
SECRET_KEY=9RV1NSDIT9S3NR5O

# Subnet of the docker network. This should not conflict with any networks to which your system is connected. (Internal and external!)
SUBNET=192.168.200.0/24

# Main mail domain
DOMAIN=$DOMAIN

# Hostnames for this server, separated with comas
HOSTNAMES=mail.$DOMAIN

# Postmaster local part (will append the main mail domain)
POSTMASTER=admin

# Choose how secure connections will behave (value: letsencrypt, cert, notls, mail, mail-letsencrypt)
TLS_FLAVOR=letsencrypt

# Authentication rate limit per IP (per /24 on ipv4 and /48 on ipv6)
AUTH_RATELIMIT_IP=5/hour

# Authentication rate limit per user (regardless of the source-IP)
AUTH_RATELIMIT_USER=50/day

# Opt-out of statistics, replace with "True" to opt out
DISABLE_STATISTICS=False

###################################
# Optional features
###################################

# Expose the admin interface (value: true, false)
ADMIN=true

# Choose which webmail to run if any (values: roundcube, snappymail, none)
WEBMAIL=roundcube

# Expose the API interface (value: true, false)
API=false

# Dav server implementation (value: radicale, none)
WEBDAV=none

# Antivirus solution (value: clamav, none)
ANTIVIRUS=clamav

# Scan Macros solution (value: true, false)
SCAN_MACROS=true

###################################
# Mail settings
###################################

# Message size limit in bytes
# Default: accept messages up to 50MB
# Max attachment size will be 33% smaller
MESSAGE_SIZE_LIMIT=50000000

# Message rate limit (per user)
MESSAGE_RATELIMIT=200/day

# Networks granted relay permissions
# Use this with care, all hosts in this networks will be able to send mail without authentication!
RELAYNETS=

# Will relay all outgoing mails if configured
RELAYHOST=

# Enable fetchmail
FETCHMAIL_ENABLED=False

# Fetchmail delay
FETCHMAIL_DELAY=600

# Recipient delimiter, character used to delimiter localpart from custom address part
RECIPIENT_DELIMITER=+

# DMARC rua and ruf email
DMARC_RUA=admin
DMARC_RUF=admin

# Welcome email, enable and set a topic and body if you wish to send welcome
# emails to all users.
WELCOME=false
WELCOME_SUBJECT=Welcome to your new email account
WELCOME_BODY=Welcome to your new email account, if you can read this, then it is configured properly!

# Maildir Compression
# choose compression-method, default: none (value: gz, bz2, zstd)
COMPRESSION=
# change compression-level, default: 6 (value: 1-9)
COMPRESSION_LEVEL=

# IMAP full-text search is enabled by default. Set the following variable to off in order to disable the feature.
# FULL_TEXT_SEARCH=off

###################################
# Web settings
###################################

# Path to redirect / to
WEBROOT_REDIRECT=/webmail

# Path to the admin interface if enabled
WEB_ADMIN=/admin

# Path to the webmail if enabled
WEB_WEBMAIL=/webmail

# Path to the API interface if enabled
WEB_API=

# Website name
SITENAME=$DOMAIN

# Linked Website URL
WEBSITE=https://$DOMAIN


###################################
# Advanced settings
###################################

# Docker-compose project name, this will prepended to containers names.
COMPOSE_PROJECT_NAME=mailu

# Number of rounds used by the password hashing scheme
CREDENTIAL_ROUNDS=12

# Header to take the real ip from
REAL_IP_HEADER=

# IPs for nginx set_real_ip_from (CIDR list separated by commas)
REAL_IP_FROM=

# choose wether mailu bounces (no) or rejects (yes) mail when recipient is unknown (value: yes, no)
REJECT_UNLISTED_RECIPIENT=

# Log level threshold in start.py (value: CRITICAL, ERROR, WARNING, INFO, DEBUG, NOTSET)
LOG_LEVEL=WARNING

# Timezone for the Mailu containers. See this link for all possible values https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ=Etc/UTC

# Default spam threshold used for new users
DEFAULT_SPAM_THRESHOLD=80

# API token required for authenticating to the RESTful API.
# This is a mandatory setting for using the RESTful API.
API_TOKEN=


INITIAL_ADMIN_ACCOUNT=admin
INITIAL_ADMIN_DOMAIN=$DOMAIN
INITIAL_ADMIN_PW=$AdminPassword
INITIAL_ADMIN_MODE=ifmissing

EOF

# Output success message
echo "Mailu configuration files have been created."

# Run docker-compose to start Mailu
echo "Starting Mailu..."
cd /mailu
docker-compose up -d

echo "Mailu has been successfully started."
echo "You can access the admin interface at: http://mail.$DOMAIN/admin"
echo "Admin email: admin@$DOMAIN"
echo "Admin password: $AdminPassword"
