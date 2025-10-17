# CEITBA Production Deployment Guide

This guide covers the external setup required on your production server to run the Dockerized nginx setup.

## Prerequisites

- Ubuntu/Debian server with SSH access
- Domain name `ceitba.org.ar` pointing to your server's IP
- Docker and Docker Compose installed
- Ports 80 and 443 open on firewall

## External Setup Required

### 1. DNS Configuration

**Before deploying**, ensure your DNS is configured:

```bash
# Check DNS is pointing to your server
dig ceitba.org.ar +short
# Should return your server's public IP
```

**Required DNS Records:**
```
Type    Name              Value
A       ceitba.org.ar     YOUR_SERVER_IP
A       www.ceitba.org.ar YOUR_SERVER_IP
```

### 2. Firewall Configuration

Open required ports on your server:

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp   # SSH (if not already open)
sudo ufw allow 80/tcp   # HTTP (for Let's Encrypt)
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable
sudo ufw status

# OR using iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

**Cloud Provider Firewall** (if applicable):
- AWS Security Groups
- GCP Firewall Rules
- Azure Network Security Groups
- DigitalOcean Cloud Firewalls

Ensure these allow inbound traffic on ports 80 and 443.

### 3. Docker Network Setup

The nginx configuration uses an external Docker network called `app-network`. This needs to be created ONCE on your server:

```bash
# Verify it exists
docker network ls | grep app-network
# or
# Create the shared network
docker network create app-network
```

**Why?** This allows nginx and all your services (API, frontend, scheduler) to communicate with each other.

### 4. SSL Certificates Setup

#### Initial Setup WITHOUT SSL (then add SSL)

**Step 1:** Temporarily modify nginx to listen only on port 80

Create a temporary `sites-enabled/temp.conf`:
```nginx
server {
    listen 80;
    server_name ceitba.org.ar www.ceitba.org.ar;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 200 'Server is running, setting up SSL...';
        add_header Content-Type text/plain;
    }
}
```

**Step 2:** Start nginx
```bash
cd /path/to/ceitba-infra
docker compose -f docker/nginx.yml up -d
```

**Step 3:** Get SSL certificates using Certbot
```bash
# Install certbot (if not installed)
sudo apt update
sudo apt install certbot

# Get certificates using webroot method
sudo certbot certonly --webroot \
  -w /var/www/certbot \
  -d ceitba.org.ar \
  -d www.ceitba.org.ar \
  --email ceitba@itba.edu.ar \
  --agree-tos \
  --no-eff-email
```

### 5. Certificate Auto-Renewal Setup

Let's Encrypt certificates expire every 90 days. Set up auto-renewal:

```bash
# Test renewal
sudo certbot renew --dry-run

# Setup auto-renewal (certbot usually does this automatically)
# Check if timer is active
sudo systemctl status certbot.timer

# OR add to crontab manually
sudo crontab -e
# Add this line:
0 3 * * * certbot renew --quiet --post-hook "docker compose -f /path/to/ceitba-infra/docker/nginx.yml exec nginx nginx -s reload"
```

### 6. Directory Structure on Server

Ensure these directories exist on your production server:

```bash
# Create certbot webroot
sudo mkdir -p /var/www/certbot
sudo chown -R www-data:www-data /var/www/certbot  # Or your user

# Verify Let's Encrypt directory (created by certbot)
ls -la /etc/letsencrypt/live/ceitba.org.ar/
```
