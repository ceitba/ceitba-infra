#!/usr/bin/env sh
# SSL Certificate Setup Script (auto-LE + fallback self-signed)
# Works in both development and production environments.

set -eu

DOMAIN="${SSL_DOMAIN:-localhost}"
ALT_NAMES="${SERVER_NAME:-}"                  # e.g., "ceitba.org.ar www.ceitba.org.ar"
EMAIL="${CERTBOT_EMAIL:-}"                    # e.g., "ceitba+cert@itba.edu.ar"
CERTBOT_MODE="${CERTBOT_MODE:-auto}"          # auto | standalone | webroot
WEBROOT_PATH="${CERTBOT_WEBROOT:-/var/www/certbot}"

# Detect if running inside container
if [ -d "/etc/nginx" ]; then
  CERT_DIR="/etc/nginx/ssl"
  LETSENCRYPT_DIR="/etc/letsencrypt"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  CERT_DIR="${SCRIPT_DIR}/ssl"
  LETSENCRYPT_DIR="/etc/letsencrypt"
fi

LE_CERT="${LETSENCRYPT_DIR}/live/${DOMAIN}/fullchain.pem"
LE_KEY="${LETSENCRYPT_DIR}/live/${DOMAIN}/privkey.pem"

log() { printf '%s\n' "$*" >&2; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Build proper "-d" flags for certbot from DOMAIN + SERVER_NAME (space-separated)
build_domain_flags() {
  DOM_FLAGS="-d ${DOMAIN}"
  # shell word-splits ALT_NAMES on spaces: "a b c"
  for name in ${ALT_NAMES}; do
    [ -z "${name}" ] && continue
    # avoid duplicates (certbot tolerates them, but let's be neat)
    [ "${name}" = "${DOMAIN}" ] && continue
    DOM_FLAGS="${DOM_FLAGS} -d ${name}"
  done
  printf '%s' "${DOM_FLAGS}"
}

port80_free() {
  # Return 0 if port 80 is free on the host
  if have_cmd ss; then ss -tulpn 2>/dev/null | grep -q ':80 ' && return 1 || return 0; fi
  if have_cmd lsof; then lsof -i :80 2>/dev/null | grep -q LISTEN && return 1 || return 0; fi
  return 0
}

emit_le_standalone() {
  log "→ Trying to issue Let's Encrypt certificate (standalone mode)…"
  if ! port80_free; then
    log "✗ Port 80 is busy — cannot use standalone mode."
    return 1
  fi

  DOM_FLAGS="$(build_domain_flags)"

  if have_cmd certbot; then
    sudo certbot certonly --non-interactive --agree-tos \
      --email "${EMAIL}" --standalone \
      ${DOM_FLAGS}
  elif have_cmd docker; then
    sudo mkdir -p "${LETSENCRYPT_DIR}"
    docker run --rm \
      -p 80:80 \
      -v "${LETSENCRYPT_DIR}:/etc/letsencrypt" \
      certbot/certbot certonly --non-interactive --agree-tos \
      --email "${EMAIL}" --standalone \
      ${DOM_FLAGS}
  else
    log "✗ No certbot or docker available to issue certificate."
    return 1
  fi
}

emit_le_webroot() {
  log "→ Trying to issue Let's Encrypt certificate (webroot mode: ${WEBROOT_PATH})…"
  sudo mkdir -p "${WEBROOT_PATH}"

  DOM_FLAGS="$(build_domain_flags)"

  if have_cmd certbot; then
    sudo certbot certonly --non-interactive --agree-tos \
      --email "${EMAIL}" --webroot -w "${WEBROOT_PATH}" \
      ${DOM_FLAGS}
  elif have_cmd docker; then
    sudo mkdir -p "${LETSENCRYPT_DIR}"
    docker run --rm \
      -v "${LETSENCRYPT_DIR}:/etc/letsencrypt" \
      -v "${WEBROOT_PATH}:${WEBROOT_PATH}" \
      certbot/certbot certonly --non-interactive --agree-tos \
      --email "${EMAIL}" --webroot -w "${WEBROOT_PATH}" \
      ${DOM_FLAGS}
  else
    log "✗ No certbot or docker available for webroot mode."
    return 1
  fi
}

ensure_le_if_needed() {
  # Issue certificate only if domain != localhost and certs are missing
  if [ "${DOMAIN}" = "localhost" ]; then
    log "INFO: DOMAIN=localhost → skipping Let's Encrypt issuance (will use self-signed)."
    return 0
  fi

  if [ -f "${LE_CERT}" ] && [ -f "${LE_KEY}" ]; then
    log "✓ Let's Encrypt certificates already exist for ${DOMAIN}"
    return 0
  fi

  if [ -z "${EMAIL}" ]; then
    log "⚠️  CERTBOT_EMAIL is empty. Cannot issue Let's Encrypt certificates automatically."
    return 1
  fi

  MODE="${CERTBOT_MODE}"
  if [ "${MODE}" = "auto" ]; then
    # In your start-all.sh order, nginx is not yet up → standalone is best.
    MODE="standalone"
  fi

  case "${MODE}" in
    standalone) emit_le_standalone || return 1 ;;
    webroot)    emit_le_webroot    || return 1 ;;
    *)          log "✗ Invalid CERTBOT_MODE: ${MODE}"; return 1 ;;
  esac

  if [ -f "${LE_CERT}" ] && [ -f "${LE_KEY}" ]; then
    log "✓ Let's Encrypt certificate successfully issued for ${DOMAIN}"
    return 0
  else
    log "✗ Certificates not found after issuance attempt."
    return 1
  fi
}

log "Setting up SSL certificates for domain: ${DOMAIN}"
log "Certificate directory: ${CERT_DIR}"
mkdir -p "${CERT_DIR}"

# 1) Try issuing LE if missing
if [ ! -f "${LE_CERT}" ] || [ ! -f "${LE_KEY}" ]; then
  if ! ensure_le_if_needed; then
    log "INFO: Let's Encrypt not available — will fall back to self-signed certificate."
  fi
fi

# 2) If LE exists, link it
if [ -f "${LE_CERT}" ] && [ -f "${LE_KEY}" ]; then
  log "✓ Using Let's Encrypt production certificates"
  ln -sf "${LE_CERT}" "${CERT_DIR}/cert.crt"
  ln -sf "${LETSENCRYPT_DIR}/live/${DOMAIN}/privkey.pem" "${CERT_DIR}/cert.key"
  ln -sf "${LETSENCRYPT_DIR}/options-ssl-nginx.conf" "${CERT_DIR}/options-ssl-nginx.conf" 2>/dev/null || true
  ln -sf "${LETSENCRYPT_DIR}/ssl-dhparams.pem" "${CERT_DIR}/dhparam.pem" 2>/dev/null || true
else
  # 3) Self-signed fallback
  log "✗ Let's Encrypt certificates not found → generating self-signed…"
  if [ ! -f "${CERT_DIR}/cert.crt" ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "${CERT_DIR}/cert.key" \
      -out "${CERT_DIR}/cert.crt" \
      -subj "/C=AR/ST=BuenosAires/L=BuenosAires/O=CEITBA/OU=Development/CN=${DOMAIN}" \
      -addext "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost,IP:127.0.0.1" \
      2>/dev/null
    log "✓ Self-signed certificate generated"
  else
    log "✓ Using existing self-signed certificate"
  fi

  if [ ! -f "${CERT_DIR}/dhparam.pem" ]; then
    log "Generating DH parameters (this may take a while)…"
    openssl dhparam -out "${CERT_DIR}/dhparam.pem" 2048 2>/dev/null
    log "✓ DH parameters generated"
  fi

  if [ ! -f "${CERT_DIR}/options-ssl-nginx.conf" ]; then
    cat > "${CERT_DIR}/options-ssl-nginx.conf" <<'EOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;

ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF
    log "✓ SSL options file created"
  fi
fi

log "SSL setup complete!"
log "Certificate: ${CERT_DIR}/cert.crt"
log "Private Key: ${CERT_DIR}/cert.key"
