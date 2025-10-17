# SSL/HTTPS Setup Guide

This nginx configuration automatically handles SSL certificates for both **local development** and **production** environments using a unified approach.

## How It Works

The setup uses an automatic SSL certificate detection system:

1. **Production (with Let's Encrypt/Certbot)**:
   - Checks for Let's Encrypt certificates at `/etc/letsencrypt/live/${SSL_DOMAIN}/`
   - If found, creates symlinks to use them
   - Full production-grade SSL with valid certificates

2. **Local Development (self-signed)**:
   - If Let's Encrypt certificates are not found
   - Automatically generates self-signed certificates
   - Works immediately without any external setup

## Configuration

### Environment Variable

Set the `SSL_DOMAIN` in your `.env` file:

```bash
# For local development
SSL_DOMAIN=localhost

# For production
SSL_DOMAIN=ceitba.org.ar
```

### Automatic Setup

The SSL setup runs automatically when:
- You run `./scripts/start-all.sh`
- The nginx container starts (via entrypoint script)

### Manual Setup

You can also run the SSL setup manually:

```bash
# Local development
SSL_DOMAIN=localhost bash nginx/setup-ssl.sh

# Production
SSL_DOMAIN=ceitba.org.ar bash nginx/setup-ssl.sh
```

## Local Development

### First Time Setup

1. Make sure `SSL_DOMAIN=localhost` in your `.env` file (or don't set it, defaults to localhost)
2. Run the deployment script:
   ```bash
   ./scripts/start-all.sh
   ```
3. Access your application:
   - **HTTP**: http://localhost (redirects to HTTPS)
   - **HTTPS**: https://localhost
   - **API Health**: https://localhost/health
   - **API Docs**: https://localhost/api/docs

### Browser Certificate Warning

Since we're using self-signed certificates, your browser will show a security warning. This is expected for local development.

**To bypass the warning:**
- **Chrome/Edge**: Click "Advanced" → "Proceed to localhost (unsafe)"
- **Firefox**: Click "Advanced" → "Accept the Risk and Continue"
- **Safari**: Click "Show Details" → "visit this website"

**To avoid warnings (optional):**
1. Import the certificate to your system's trust store
2. Or use tools like [mkcert](https://github.com/FiloSottile/mkcert) for locally-trusted certificates

## Production Setup

### Prerequisites

1. Domain pointing to your server (A record)
2. Ports 80 and 443 open in firewall
3. Certbot installed on the server

### Option A: Get Certificates Before Deployment

```bash
# Install certbot if needed
sudo apt update
sudo apt install certbot

# Get certificates (standalone mode - nginx must be stopped)
sudo certbot certonly --standalone \
  -d ceitba.org.ar \
  -d www.ceitba.org.ar \
  --email your-email@example.com \
  --agree-tos

# Certificates will be at /etc/letsencrypt/live/ceitba.org.ar/
```

### Option B: Get Certificates With Nginx Running

1. First deployment with self-signed certificates:
   ```bash
   SSL_DOMAIN=ceitba.org.ar ./scripts/start-all.sh
   ```

2. Get Let's Encrypt certificates using webroot:
   ```bash
   sudo certbot certonly --webroot \
     -w /var/www/certbot \
     -d ceitba.org.ar \
     -d www.ceitba.org.ar \
     --email your-email@example.com \
     --agree-tos
   ```

3. Reload nginx to use new certificates:
   ```bash
   docker exec ceitba-nginx nginx -s reload
   ```

### Certificate Auto-Renewal

Let's Encrypt certificates expire every 90 days. Set up auto-renewal:

```bash
# Test renewal
sudo certbot renew --dry-run

# Add to crontab for auto-renewal
sudo crontab -e

# Add this line (runs daily at 3 AM, renews if needed)
0 3 * * * certbot renew --quiet --post-hook "docker exec ceitba-nginx nginx -s reload"
```

## SSL Certificate Paths

The system uses unified certificate paths that work in both environments:

| File | Path in Container | Purpose |
|------|------------------|---------|
| Certificate | `/etc/nginx/ssl/cert.crt` | Public certificate |
| Private Key | `/etc/nginx/ssl/cert.key` | Private key |
| SSL Options | `/etc/nginx/ssl/options-ssl-nginx.conf` | SSL configuration |
| DH Params | `/etc/nginx/ssl/dhparam.pem` | Diffie-Hellman parameters |

**In Production with Let's Encrypt:**
- These are symlinks to `/etc/letsencrypt/live/${SSL_DOMAIN}/`

**In Development:**
- These are actual self-signed certificate files

## Troubleshooting

### Nginx fails to start

Check SSL certificate setup:
```bash
# View setup logs
docker logs ceitba-nginx | grep -A 10 "Setting up SSL"

# Manually run setup
SSL_DOMAIN=localhost bash nginx/setup-ssl.sh

# Check if certificates exist
ls -la nginx/ssl/
```

### Certificate warnings in production

1. Verify Let's Encrypt certificates exist:
   ```bash
   sudo ls -la /etc/letsencrypt/live/ceitba.org.ar/
   ```

2. Check if nginx is using them:
   ```bash
   docker exec ceitba-nginx ls -la /etc/nginx/ssl/
   ```

3. Test SSL configuration:
   ```bash
   docker exec ceitba-nginx nginx -t
   ```

### Update certificates after renewal

```bash
# Reload nginx to pick up renewed certificates
docker exec ceitba-nginx nginx -s reload

# Or restart the container
docker compose -f docker/nginx.yml restart
```

## Security Notes

### Development
- ⚠️ Self-signed certificates provide encryption but not authentication
- Only use for local development, never in production
- Browser will show security warnings (this is expected)

### Production
- ✅ Let's Encrypt provides valid, trusted certificates
- ✅ Automatic HTTPS redirection enabled
- ✅ HSTS headers enabled (forces HTTPS)
- ✅ Modern SSL/TLS configuration (TLS 1.2+)
- ✅ Strong cipher suites configured

## Files Overview

- `nginx/setup-ssl.sh` - Automatic SSL setup script
- `nginx/ssl/` - SSL certificates directory
- `nginx/sites-enabled/default.conf` - Nginx site configuration
- `docker/nginx.yml` - Nginx container configuration
- `.env` - Environment configuration (SSL_DOMAIN)

## Migration Between Environments

The same configuration works everywhere. Just change `SSL_DOMAIN`:

```bash
# Development → Production
# 1. Update .env
SSL_DOMAIN=ceitba.org.ar

# 2. Get Let's Encrypt certificates (if not done)
sudo certbot certonly --webroot -w /var/www/certbot -d ceitba.org.ar

# 3. Redeploy
./scripts/start-all.sh
```

No nginx configuration changes needed! 🎉
