#!/bin/bash
# Container runtime supervisor.
#
# tini is PID 1 and forwards signals to this process group. This wrapper keeps
# the existing configuration entrypoint focused on Koha setup while providing
# one place for graceful, ordered shutdown of the services it starts.

set -u

LIBRARY_NAME="${LIBRARY_NAME:-defaultlibraryname}"
KOHA_WORKERS_ENABLED="${KOHA_WORKERS_ENABLED:-yes}"
KOHA_CRON_ENABLED="${KOHA_CRON_ENABLED:-yes}"

entrypoint_pid=""
shutting_down=0

stop_koha_services() {
    echo "*** Stopping Koha services..."

    # Stop accepting new work before stopping the workers/backends.
    apachectl -k graceful-stop 2>/dev/null || true

    if [ "$KOHA_CRON_ENABLED" = "yes" ]; then
        service cron stop 2>/dev/null || true
    fi

    if [ "$KOHA_WORKERS_ENABLED" = "yes" ]; then
        koha-worker --stop --queue long_tasks "$LIBRARY_NAME" 2>/dev/null || true
        koha-worker --stop --queue default "$LIBRARY_NAME" 2>/dev/null || true
    fi

    koha-indexer --stop "$LIBRARY_NAME" 2>/dev/null || true
    koha-zebra --stop "$LIBRARY_NAME" 2>/dev/null || true
    koha-plack --stop "$LIBRARY_NAME" 2>/dev/null || true
}

shutdown() {
    local status="${1:-0}"

    if [ "$shutting_down" -eq 1 ]; then
        return
    fi
    shutting_down=1
    trap - TERM INT

    echo "*** Shutdown requested"
    stop_koha_services

    if [ -n "$entrypoint_pid" ] && kill -0 "$entrypoint_pid" 2>/dev/null; then
        kill -TERM "$entrypoint_pid" 2>/dev/null || true
        wait "$entrypoint_pid" 2>/dev/null || true
    fi

    exit "$status"
}

trap 'shutdown 0' TERM INT

/docker/entrypoint.sh &
entrypoint_pid=$!

wait "$entrypoint_pid"
status=$?

if [ "$shutting_down" -eq 0 ]; then
    echo "*** Koha entrypoint exited with status $status"
    stop_koha_services
fi

exit "$status"
