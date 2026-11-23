#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo 'Create .env with SERPAPI_API_KEY or DUFFEL_TOKEN first.' >&2
  exit 1
fi
if curl --silent --max-time 1 http://127.0.0.1:8787/ >/dev/null; then
  echo 'Port 8787 is already in use. Stop the previous Worker first.' >&2
  exit 1
fi

node --env-file=.env worker/dev.mjs &
worker_pid=$!
trap 'kill "$worker_pid" 2>/dev/null || true; wait "$worker_pid" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for _ in {1..30}; do
  kill -0 "$worker_pid" 2>/dev/null || exit 1
  if curl --silent --max-time 1 http://127.0.0.1:8787/ >/dev/null; then
    flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080 \
      --dart-define=FLIGHTS_API_URL=http://127.0.0.1:8787 "$@"
    exit
  fi
  sleep 0.1
done
echo 'The local flight Worker did not start.' >&2
exit 1
