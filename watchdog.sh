#!/bin/bash
# Watchdog: monitors Koha via HTTP probes and restarts Plack on persistent failure.
#
# Apache runs in the foreground and keeps the container alive even if the
# Plack/Starman backend has crashed or wedged. When that happens Apache
# returns 502/503/504 and Docker's restart policy does not help. This
# script detects those situations via HTTP probes and restarts Plack
# in place.
#
# Note: koha-plack / koha-zebra do not have a reliable --status
# subcommand across versions, so we deliberately do not try to inspect
# them directly. The HTTP probe is the signal that actually matters
# for the user-facing 503.

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

# Returns 0 if Apache responds with anything other than a proxy error,
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

    if http_ok "$OPACPORT"; then
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
        if http_ok "$INTRAPORT"; then
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
