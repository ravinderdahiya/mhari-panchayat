# Running the backend for ~10,000 active users

Found by load testing (200k complaints, 100k assets, 500k notifications, 10k citizens) on 8 PHP workers:
one worker serves roughly 11 requests/second, and the app's unread-count polling alone is ~1 request per
user per poll interval. These settings are what moves the numbers; they are server settings, not code.

## `.env` on the production server

```
APP_ENV=production
APP_DEBUG=false
LOG_LEVEL=warning

# Keep one PostgreSQL connection per php-fpm worker. Opening one costs ~40 ms, about half of a request.
DB_PERSISTENT=true

# Behind nginx / a load balancer / Cloudflare. Without this every visitor looks like the proxy's IP and
# shares ONE rate-limit bucket (throttle:60,1 would then be 60 requests/minute for the whole country).
TRUSTED_PROXIES=*            # or the proxy's IP / CIDR list

# Cache + rate limiter off the database (every throttled request otherwise reads and writes a table).
CACHE_STORE=redis
REDIS_HOST=127.0.0.1
SESSION_DRIVER=array         # the API is token based, sessions are not used
QUEUE_CONNECTION=redis       # or database, with a supervised `php artisan queue:work`
```

## php-fpm (`www.conf`)

```
pm = static
pm.max_children = 32          ; ~ cores x 2-4; each worker is one in-flight request
pm.max_requests = 500
request_terminate_timeout = 20s
```

- PostgreSQL `max_connections` must be larger than `pm.max_children` plus queue workers (default is 100).
  If you need more workers than that, put **pgbouncer** (transaction pooling) in front and turn `DB_PERSISTENT` off.
- PHP: `opcache.enable=1`, `opcache.validate_timestamps=0` (reload php-fpm on each deploy), `opcache.memory_consumption=256`.

## Every deploy

```
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache && php artisan route:cache && php artisan event:cache
```

## What protects workers from slow outside services

Capture GPS calls the GIS boundary service and Nominatim. They now give up after 3-4 seconds, and once one has
failed it is skipped for a minute (`GisController::BREAKER_SECONDS`), so an outage costs one short wait instead of
holding every worker for 10-30 seconds. The geofence then lets the complaint through (it cannot judge the point).

## Capacity rule of thumb

`requests/second one worker can serve` ~ `1 / request time`. A cached public request is ~45 ms with a persistent
connection, so ~22 requests/second per worker; 32 workers ~ 700 requests/second. Citizens poll every 2-3 minutes,
so 10,000 active users are ~70 requests/second of polling, with room left for browsing and complaints.
