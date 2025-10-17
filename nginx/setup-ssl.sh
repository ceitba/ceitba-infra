#!/bin/sh
# SSL Certificate Setup Script
# Works in both development and production environments

DOMAIN="${SSL_DOMAIN:-localhost}"

# Detect if running in container or on host
if [ -d "/etc/nginx" ]; then
    # Running in container
    CERT_DIR="/etc/nginx/ssl"
    LETSENCRYPT_DIR="/etc/letsencrypt"
else
    # Running on host - use script directory
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    CERT_DIR="${SCRIPT_DIR}/ssl"
    LETSENCRYPT_DIR="/etc/letsencrypt"
fi

LETSENCRYPT_CERT="${LETSENCRYPT_DIR}/live/${DOMAIN}/fullchain.pem"
LETSENCRYPT_KEY="${LETSENCRYPT_DIR}/live/${DOMAIN}/privkey.pem"

echo "Setting up SSL certificates for domain: ${DOMAIN}"
echo "Certificate directory: ${CERT_DIR}"

# Create SSL directory if it doesn't exist
mkdir -p ${CERT_DIR}

# Check if Let's Encrypt certificates exist (production)
if [ -f "${LETSENCRYPT_CERT}" ] && [ -f "${LETSENCRYPT_KEY}" ]; then
    echo "✓ Found Let's Encrypt certificates for ${DOMAIN}"
    echo "  Using production SSL certificates"

    # Create symlinks to Let's Encrypt certificates
    ln -sf "${LETSENCRYPT_CERT}" ${CERT_DIR}/cert.crt
    ln -sf "${LETSENCRYPT_KEY}" ${CERT_DIR}/cert.key
    ln -sf ${LETSENCRYPT_DIR}/options-ssl-nginx.conf ${CERT_DIR}/options-ssl-nginx.conf 2>/dev/null || true
    ln -sf ${LETSENCRYPT_DIR}/ssl-dhparams.pem ${CERT_DIR}/dhparam.pem 2>/dev/null || true

else
    echo "✗ Let's Encrypt certificates not found"
    echo "  Generating self-signed certificates for development..."

    # Generate self-signed certificate if it doesn't exist
    if [ ! -f "${CERT_DIR}/cert.crt" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ${CERT_DIR}/cert.key \
            -out ${CERT_DIR}/cert.crt \
            -subj "/C=AR/ST=BuenosAires/L=BuenosAires/O=CEITBA/OU=Development/CN=${DOMAIN}" \
            -addext "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost,IP:127.0.0.1" \
            2>/dev/null

        echo "✓ Self-signed certificate generated"
    else
        echo "✓ Using existing self-signed certificate"
    fi

    # Generate DH params if they don't exist
    if [ ! -f "${CERT_DIR}/dhparam.pem" ]; then
        echo "  Generating DH parameters (this may take a minute)..."
        openssl dhparam -out ${CERT_DIR}/dhparam.pem 2048 2>/dev/null
        echo "✓ DH parameters generated"
    fi

    # Create SSL options file if it doesn't exist
    if [ ! -f "${CERT_DIR}/options-ssl-nginx.conf" ]; then
        cat > ${CERT_DIR}/options-ssl-nginx.conf <<EOF
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;

ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF
        echo "✓ SSL options file created"
    fi
fi

echo "SSL setup complete!"
echo "Certificate: ${CERT_DIR}/cert.crt"
echo "Private Key: ${CERT_DIR}/cert.key"
