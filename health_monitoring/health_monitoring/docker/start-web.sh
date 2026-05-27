#!/bin/sh
set -e

: "${PORT:=8080}"
export PORT

envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

php artisan migrate --force --no-interaction

php artisan config:cache
php artisan route:cache
php artisan event:cache

exec /usr/bin/supervisord -c /etc/supervisord.conf
