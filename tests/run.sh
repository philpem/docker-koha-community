#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

scripts=(
    entrypoint.sh
    runtime.sh
    state.sh
    watchdog.sh
    healthcheck.sh
    healthz-probe.sh
    http-probe.sh
    tests/test-state.sh
    tests/test-http-probe.sh
    tests/run.sh
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

./tests/test-state.sh
./tests/test-http-probe.sh

echo "all tests: OK"
