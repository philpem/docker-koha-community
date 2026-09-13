#!/bin/bash
# Watchdog: monitors Koha via /healthz and restarts Plack on persistent
# application-path failure.
#
# /healthz exercises Apache -> Plack/Starman -> Koha -> MariaDB without
# creating a Koha session. The probe distinguishes a known database-only
# failure from a broken proxy/Plack path so a MariaDB outage does not cause a
# pointless Plack restart loop.

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

restart_plack() {
    log "Restarting Plack for $LIBRARY_NAME"
    if ! koha-plack --restart "$LIBRARY_NAME" 2>&1; then
        log "koha-plack --restart failed, trying --start"
        koha-plack --start "$LIBRARY_NAME" 2>&1 || log "koha-plack --start also failed"
    fi
}

opac_failures=0
intra_failures=0
database_unhealthy=0

log "starting (interval=${WATCHDOG_INTERVAL}s, http_timeout=${WATCHDOG_HTTP_TIMEOUT}s, instance=${LIBRARY_NAME})"

while true; do
    sleep "$WATCHDOG_INTERVAL"

    restarted=0

    WATCHDOG_HTTP_TIMEOUT="$WATCHDOG_HTTP_TIMEOUT" /docker/healthz-probe.sh "$OPACPORT"
    result=$?
    case "$result" in
        0)
            opac_failures=0
            if [ "$database_unhealthy" -eq 1 ]; then
                log "Database health check recovered"
                database_unhealthy=0
            fi
            ;;
        2)
            opac_failures=0
            intra_failures=0
            if [ "$database_unhealthy" -eq 0 ]; then
                log "Koha is reachable but the database health check failed; not restarting Plack"
                database_unhealthy=1
            fi
            # Both virtual hosts reach the same Plack worker/database check, so
            # a confirmed database failure makes the second probe redundant.
            continue
            ;;
        *)
            database_unhealthy=0
            opac_failures=$((opac_failures + 1))
            log "OPAC /healthz probe on :${OPACPORT} failed (${opac_failures}/${WATCHDOG_HTTP_FAILURES})"
            if [ "$opac_failures" -ge "$WATCHDOG_HTTP_FAILURES" ]; then
                restart_plack
                restarted=1
                opac_failures=0
                intra_failures=0
            fi
            ;;
    esac

    if [ "$restarted" = 0 ]; then
        WATCHDOG_HTTP_TIMEOUT="$WATCHDOG_HTTP_TIMEOUT" /docker/healthz-probe.sh "$INTRAPORT"
        result=$?
        case "$result" in
            0)
                intra_failures=0
                if [ "$database_unhealthy" -eq 1 ]; then
                    log "Database health check recovered"
                    database_unhealthy=0
                fi
                ;;
            2)
                opac_failures=0
                intra_failures=0
                if [ "$database_unhealthy" -eq 0 ]; then
                    log "Koha is reachable but the database health check failed; not restarting Plack"
                    database_unhealthy=1
                fi
                ;;
            *)
                database_unhealthy=0
                intra_failures=$((intra_failures + 1))
                log "Intranet /healthz probe on :${INTRAPORT} failed (${intra_failures}/${WATCHDOG_HTTP_FAILURES})"
                if [ "$intra_failures" -ge "$WATCHDOG_HTTP_FAILURES" ]; then
                    restart_plack
                    opac_failures=0
                    intra_failures=0
                fi
                ;;
        esac
    fi
done
