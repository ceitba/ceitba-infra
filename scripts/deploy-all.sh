#!/bin/bash

echo "Creating shared network..."
docker network create app-network 2>/dev/null || true

echo "Deploying infrastructure services..."
docker-compose -f docker/nginx.yml up -d
docker-compose -f docker/management.yml up -d

echo "Deploying applications..."
docker-compose -f docker/apps.yml up -d

echo "Waiting for services to be healthy..."
sleep 30

echo "Checking service health..."
curl -f http://localhost/health || echo "API health check failed"

echo "Deployment complete!"
echo "Services available at:"
echo "- Portainer: http://localhost:9000"
