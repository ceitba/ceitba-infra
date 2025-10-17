# CEITBA Nginx Configuration

Professional nginx reverse proxy configuration for CEITBA infrastructure.

## Overview

This nginx setup provides:
- **SSL/TLS termination** with Let's Encrypt certificates
- **Reverse proxy** for multiple services (API, Frontend, Scheduler)
- **Security headers** and best practices
- **Rate limiting** to prevent abuse
- **Performance optimization** with caching and compression
- **HTTP/2** support
- **Logging** with detailed request metrics

## Directory Structure

```
nginx/
├── nginx.conf              # Main nginx configuration
├── mime.types              # MIME type definitions
├── sites-enabled/          # Virtual host configurations
│   └── default.conf        # Main ceitba.org.ar configuration
└── snippets/               # Reusable configuration snippets
    ├── proxy-params.conf   # Common proxy headers
    ├── ssl-params.conf     # SSL/TLS settings
    └── security-headers.conf # Security headers
```

## Services Configuration

### API Service (`/api/v1/`)
- **Upstream:** `ceitba-api:3000`
- **Rate limit:** 10 req/s (burst 20)
- **Timeout:** 60s
- **WebSocket:** Supported

### Frontend Service (`/`)
- **Upstream:** `ceitba-frontend:3000`
- **Rate limit:** 50 req/s (burst 50)
- **Timeout:** 60s
- **WebSocket:** Supported (for hot reload)

### Scheduler Service (`/scheduler`)
- **Upstream:** `ceitba-scheduler:3002`
- **Rate limit:** 50 req/s (burst 30)
- **Timeout:** 60s
- **WebSocket:** Supported

### Health Check (`/health`)
- **Upstream:** `ceitba-api:3000/health`
- **Rate limit:** None (for monitoring)
- **Logging:** Disabled

## Security Features

### SSL/TLS
- TLS 1.2 and 1.3 only
- Modern cipher suites
- OCSP stapling enabled
- Session tickets disabled
- HSTS enabled (1 year)

### Headers
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy` (configured)
- `Strict-Transport-Security` (HSTS)

### Rate Limiting
- API endpoints: 10 requests/second
- General endpoints: 50 requests/second
- Connection limit: 10 per IP

## Performance Optimizations

- **Gzip compression** for text/json/css/js
- **HTTP/2** enabled
- **Keepalive connections** to upstreams
- **Connection pooling** (32 connections for API/Frontend, 16 for Scheduler)
- **Buffering** optimized for performance
- **Sendfile** and **tcp_nopush** enabled

## Logging

### Access Logs
Location: `/var/log/nginx/ceitba-access.log`

Format includes:
- Request time
- Upstream connect/header/response time
- Client IP and forwarded IPs
- Request details

### Error Logs
Location: `/var/log/nginx/ceitba-error.log`
Level: `warn`

## Usage

### Starting nginx
```bash
docker compose -f docker/nginx.yml up -d
```

### Reloading Configuration
```bash
docker compose -f docker/nginx.yml exec nginx nginx -s reload
```

### Testing Configuration
```bash
docker compose -f docker/nginx.yml exec nginx nginx -t
```

### Viewing Logs
```bash
# Access logs
docker compose -f docker/nginx.yml logs -f nginx

# Real-time access log
docker compose -f docker/nginx.yml exec nginx tail -f /var/log/nginx/ceitba-access.log

# Error log
docker compose -f docker/nginx.yml exec nginx tail -f /var/log/nginx/ceitba-error.log
```

## SSL Certificate Setup

### Initial Setup with Certbot
1. Ensure port 80 is accessible
2. Run certbot in standalone or webroot mode:
   ```bash
   certbot certonly --webroot -w /var/www/certbot -d ceitba.org.ar -d www.ceitba.org.ar
   ```

### Certificate Renewal
Certificates auto-renew via certbot. The configuration includes:
- `.well-known/acme-challenge/` path for ACME challenges
- HTTP to HTTPS redirect (except for ACME challenges)

## Customization

### Adding New Services
1. Define upstream in `nginx.conf`:
   ```nginx
   upstream service_name {
       server container-name:port max_fails=3 fail_timeout=30s;
       keepalive 32;
   }
   ```

2. Add location block in `sites-enabled/default.conf`:
   ```nginx
   location /service-path {
       include snippets/proxy-params.conf;
       proxy_pass http://service_name;
   }
   ```

### Adjusting Rate Limits
Edit the `limit_req_zone` directives in `nginx.conf`:
```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
```

### Modifying Security Headers
Edit `snippets/security-headers.conf` or override in specific server blocks.

## Troubleshooting

### Check nginx status
```bash
docker compose -f docker/nginx.yml ps nginx
```

### Validate configuration
```bash
docker compose -f docker/nginx.yml exec nginx nginx -t
```

### Common Issues

1. **502 Bad Gateway**: Backend service not running
   - Check upstream services: `docker compose -f docker/apps.yml ps`

2. **Too many redirects**: Check redirect loop in configuration
   - Verify `X-Forwarded-Proto` header is set

3. **SSL errors**: Certificate issues
   - Check certificate files exist in `/etc/letsencrypt/live/ceitba.org.ar/`
   - Verify certificate validity: `openssl x509 -in /etc/letsencrypt/live/ceitba.org.ar/fullchain.pem -noout -dates`

## Production Checklist

- [ ] SSL certificates installed and valid
- [ ] DNS pointing to server (A record for ceitba.org.ar)
- [ ] Firewall allows ports 80 and 443
- [ ] All upstream services running
- [ ] Rate limits configured appropriately
- [ ] Log rotation configured (Docker handles this)
- [ ] Monitoring/alerting set up for nginx
- [ ] Backup strategy for certificates

## Monitoring

Key metrics to monitor:
- Request rate and response times
- Error rate (4xx, 5xx)
- Upstream health
- SSL certificate expiry
- Connection pool saturation

## References

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Let's Encrypt](https://letsencrypt.org/)
