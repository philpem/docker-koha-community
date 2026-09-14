#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

scripts=(
    entrypoint.sh
    runtime.sh
    state.sh
    generate-marc003-xslts.sh
    watchdog.sh
    healthcheck.sh
    healthz-probe.sh
    http-probe.sh
    tests/test-state.sh
    tests/test-http-probe.sh
    tests/test-marc003-xslts.sh
    tests/test-reconnect-db.sh
    tests/test-plack-config.sh
    tests/test-runtime-lifecycle.sh
    tests/run.sh
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

./tests/test-state.sh
./tests/test-http-probe.sh
bash ./tests/test-marc003-xslts.sh
bash ./tests/test-reconnect-db.sh
bash ./tests/test-plack-config.sh
bash ./tests/test-runtime-lifecycle.sh

echo "all tests: OK"
