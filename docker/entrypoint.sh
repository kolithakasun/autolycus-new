#!/bin/bash
set -e

mkdir -p /downloads /app/logs

if [[ ! -d /app/jackett ]]; then
    if [[ -f /app/jackett.tar ]]; then
        tar -xf /app/jackett.tar -C /app
    else
        echo "jackett.tar was not found" >&2
        exit 1
    fi
fi

python - <<'PY'
import os
import sys
import time
import urllib.request

import redis
from pymongo import MongoClient

mongo_uri = os.environ["MONGO_DATABASE_URI"]
redis_host = os.environ.get("REDIS_HOST", "redis")
redis_port = int(os.environ.get("REDIS_PORT", "6379"))
redis_password = os.environ.get("REDIS_PASSWORD") or None
meili_host = os.environ.get("MEILI_SEARCH_HOST", "http://meilisearch:7700")

for attempt in range(1, 31):
    try:
        MongoClient(mongo_uri, serverSelectionTimeoutMS=2000).admin.command("ping")
        redis.Redis(
            host=redis_host,
            port=redis_port,
            password=redis_password,
            socket_connect_timeout=2,
        ).ping()
        with urllib.request.urlopen(meili_host.rstrip("/") + "/health", timeout=2) as response:
            if response.status >= 400:
                raise RuntimeError(f"meilisearch health returned {response.status}")
        print("mongodb, redis, and meilisearch are ready")
        sys.exit(0)
    except Exception as exc:
        print(f"waiting for dependencies ({attempt}/30): {exc}")
        time.sleep(2)

print("dependencies did not become ready", file=sys.stderr)
sys.exit(1)
PY

cd /app
workers="${CELERY_NUM_WORKERS:-2}"
celery -A celery_worker worker -Q transcoding,archive,file_operations \
    --concurrency="$workers" --loglevel=info -E &
celery_pid=$!

uvicorn main:app --host 127.0.0.1 --port 8000 &
api_pid=$!

cd /ui
node node_modules/next/dist/bin/next start -H 127.0.0.1 -p 3000 &
ui_pid=$!

for _ in $(seq 1 60); do
    api_ready=0
    ui_ready=0
    python -c 'import socket; socket.create_connection(("127.0.0.1", 8000), 2).close()' >/dev/null 2>&1 && api_ready=1
    python -c 'import socket; socket.create_connection(("127.0.0.1", 3000), 2).close()' >/dev/null 2>&1 && ui_ready=1
    if [[ "$api_ready" == 1 && "$ui_ready" == 1 ]]; then
        break
    fi
    if ! kill -0 "$api_pid" 2>/dev/null || ! kill -0 "$ui_pid" 2>/dev/null; then
        echo "api or ui exited before it started listening" >&2
        exit 1
    fi
    sleep 1
done

nginx -g "daemon off;" &
nginx_pid=$!

shutdown() {
    kill "$celery_pid" "$api_pid" "$ui_pid" "$nginx_pid" 2>/dev/null || true
    wait "$celery_pid" "$api_pid" "$ui_pid" "$nginx_pid" 2>/dev/null || true
}

trap shutdown TERM INT
wait -n
status=$?
shutdown
exit "$status"
