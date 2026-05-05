#!/bin/bash
# Watchdog: monitors Koha background services and restarts them when they fail.
#
# Apache runs in the foreground and keeps the container alive even if the
# Plack/Starman backend, Zebra, or the indexer have crashed. When that happens
# Apache responds with 503 (proxy unreachable) and Docker's restart policy
# does not help. This script detects those situations and restarts the
# affected service in place.

set -u

LIBRARY_NAME="${LIBRARY_NAME:-defaultlibraryname}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"
WATCHDOG_HTTP_TIMEOUT="${WATCHDOG_HTTP_TIMEOUT:-10}"
WATCHDOG_HTTP_FAILURES="${WATCHDOG_HTTP_FAILURES:-2}"
OPACPORT="${OPACPORT:-80}"
INTRAPORT="${INTRAPORT:-8080}"

log() {
    echo "[watchdog $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

service_running() {
    # $1 = koha-plack | koha-zebra | koha-indexer
    "$1" --status "$LIBRARY_NAME" 2>&1 | grep -qi "is running"
}

restart_service() {
    local svc="$1"
    log "$svc is not running for $LIBRARY_NAME — restarting"
    if ! "$svc" --restart "$LIBRARY_NAME" 2>&1; then
        log "$svc --restart failed, trying --start"
        "$svc" --start "$LIBRARY_NAME" 2>&1 || log "$svc --start also failed"
    fi
}

# Returns 0 if Apache+Plack respond with anything other than a proxy error,
# 1 if we got 502/503/504 or no response at all.
http_ok() {
    local port="$1"
    local code
    code=$(curl -fsS -o /dev/null -w '%{http_code}' \
        --max-time "$WATCHDOG_HTTP_TIMEOUT" \
        -L --max-redirs 3 \
        "http://127.0.0.1:${port}/" 2>/dev/null || echo "000")
    case "$code" in
        000|502|503|504) return 1 ;;
        *) return 0 ;;
    esac
}

opac_failures=0
intra_failures=0

log "starting (interval=${WATCHDOG_INTERVAL}s, http_timeout=${WATCHDOG_HTTP_TIMEOUT}s, instance=${LIBRARY_NAME})"

while true; do
    sleep "$WATCHDOG_INTERVAL"

    # Process-level checks. koha-plack is the most common culprit for 503s.
    if ! service_running koha-plack; then
        restart_service koha-plack
    fi
    if ! service_running koha-zebra; then
        restart_service koha-zebra
    fi
    if ! service_running koha-indexer; then
        restart_service koha-indexer
    fi

    # HTTP-level checks. Catches the case where the plack process exists
    # but is wedged (deadlocked DB handle, stuck worker, etc.).
    if http_ok "$OPACPORT"; then
        opac_failures=0
    else
        opac_failures=$((opac_failures + 1))
        log "OPAC probe on :${OPACPORT} failed (${opac_failures}/${WATCHDOG_HTTP_FAILURES})"
        if [ "$opac_failures" -ge "$WATCHDOG_HTTP_FAILURES" ]; then
            restart_service koha-plack
            opac_failures=0
        fi
    fi

    if http_ok "$INTRAPORT"; then
        intra_failures=0
    else
        intra_failures=$((intra_failures + 1))
        log "Intranet probe on :${INTRAPORT} failed (${intra_failures}/${WATCHDOG_HTTP_FAILURES})"
        if [ "$intra_failures" -ge "$WATCHDOG_HTTP_FAILURES" ]; then
            restart_service koha-plack
            intra_failures=0
        fi
    fi
done
