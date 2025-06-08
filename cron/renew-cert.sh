#!/bin/bash
set -e

DOMAIN="${DOMAIN_NAME:-yourdomain.com}"
EMAIL="${EMAIL:-admin@yourdomain.com}"

echo "🔁 Renewing certificate for $DOMAIN ..."

docker run --rm \
  -v $HOME/.certbot/etc:/etc/letsencrypt \
  -v $HOME/.certbot/lib:/var/lib/letsencrypt \
  -v $HOME/.certbot/logs:/var/log/letsencrypt \
  certbot/certbot renew --quiet

docker restart nginx-reverse-proxy

echo "✅ Certificate renewed and NGINX restarted!"
