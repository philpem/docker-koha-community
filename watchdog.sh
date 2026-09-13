#!/bin/bash
# Watchdog: monitors Koha via HTTP probes and restarts Plack on persistent failure.
#
# Apache runs in the foreground and keeps the container alive even if the
# Plack/Starman backend has crashed or wedged. When that happens Apache
# returns an error while the container itself remains running. This script
# detects those situations via the same cookie-preserving application probe
# used by Docker HEALTHCHECK and restarts Plack in place.

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

http_ok() {
    local port="$1"
    local cookie_jar="$2"
    WATCHDOG_HTTP_TIMEOUT="$WATCHDOG_HTTP_TIMEOUT" \
        /docker/http-probe.sh "$port" "$cookie_jar"
}

restart_plack() {
    log "Restarting Plack for $LIBRARY_NAME"
    if ! koha-plack --restart "$LIBRARY_NAME" 2>&1; then
        log "koha-plack --restart failed, trying --start"
        koha-plack --start "$LIBRARY_NAME" 2>&1 || log "koha-plack --start also failed"
    fi
}

opac_failures=0
intra_failures=0

log "starting (interval=${WATCHDOG_INTERVAL}s, http_timeout=${WATCHDOG_HTTP_TIMEOUT}s, instance=${LIBRARY_NAME})"

while true; do
    sleep "$WATCHDOG_INTERVAL"

    restarted=0

    if http_ok "$OPACPORT" /run/koha-health/watchdog-opac.cookies; then
        opac_failures=0
    else
        opac_failures=$((opac_failures + 1))
        log "OPAC probe on :${OPACPORT} failed (${opac_failures}/${WATCHDOG_HTTP_FAILURES})"
        if [ "$opac_failures" -ge "$WATCHDOG_HTTP_FAILURES" ]; then
            restart_plack
            restarted=1
            opac_failures=0
            intra_failures=0
        fi
    fi

    if [ "$restarted" = 0 ]; then
        if http_ok "$INTRAPORT" /run/koha-health/watchdog-intranet.cookies; then
            intra_failures=0
        else
            intra_failures=$((intra_failures + 1))
            log "Intranet probe on :${INTRAPORT} failed (${intra_failures}/${WATCHDOG_HTTP_FAILURES})"
            if [ "$intra_failures" -ge "$WATCHDOG_HTTP_FAILURES" ]; then
                restart_plack
                opac_failures=0
                intra_failures=0
            fi
        fi
    fi
done
