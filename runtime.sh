#!/bin/bash
# Container runtime supervisor.
#
# tini is PID 1 and reaps orphaned children. Docker termination signals reach
# this supervisor, which keeps the existing configuration entrypoint focused on
# Koha setup while providing one place for graceful, ordered shutdown.

set -Eeuo pipefail

LIBRARY_NAME="${LIBRARY_NAME:-defaultlibraryname}"
KOHA_WORKERS_ENABLED="${KOHA_WORKERS_ENABLED:-yes}"
KOHA_CRON_ENABLED="${KOHA_CRON_ENABLED:-yes}"

entrypoint_pid=""
shutting_down=0

instance_feature_enabled() {
    local feature="$1"
    koha-list --enabled "--${feature}" | grep -Fxq "$LIBRARY_NAME"
}

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

    # Only stop optional daemons which are configured for this instance. This
    # avoids noisy "not running" errors during normal shutdown.
    if instance_feature_enabled elasticsearch; then
        koha-es-indexer --stop --quiet "$LIBRARY_NAME" >/dev/null 2>&1 || true
    fi
    if instance_feature_enabled z3950; then
        koha-z3950-responder --stop --quiet "$LIBRARY_NAME" >/dev/null 2>&1 || true
    fi
    if instance_feature_enabled sip; then
        koha-sip --stop "$LIBRARY_NAME" >/dev/null 2>&1 || true
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

if wait "$entrypoint_pid"; then
    status=0
else
    status=$?
fi

if [ "$shutting_down" -eq 0 ]; then
    echo "*** Koha entrypoint exited with status $status"
    stop_koha_services
fi

exit "$status"
