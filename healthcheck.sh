#!/bin/bash
# Docker HEALTHCHECK probe for Koha.
#
# Returns 0 (healthy) when both the OPAC and the staff intranet respond with
# a non-error HTTP status. 502/503/504 (or no response) mean Apache could not
# reach Plack — the watchdog will normally recover from this, but Docker
# can also use the unhealthy status to restart the container if it persists.

set -u

OPACPORT="${OPACPORT:-80}"
INTRAPORT="${INTRAPORT:-8080}"
HEALTHCHECK_TIMEOUT="${HEALTHCHECK_TIMEOUT:-10}"

probe() {
    local port="$1"
    local code
    code=$(curl -fsS -o /dev/null -w '%{http_code}' \
        --max-time "$HEALTHCHECK_TIMEOUT" \
        -L --max-redirs 3 \
        "http://127.0.0.1:${port}/" 2>/dev/null || echo "000")
    case "$code" in
        000|502|503|504) return 1 ;;
        *) return 0 ;;
    esac
}

probe "$OPACPORT" || exit 1
probe "$INTRAPORT" || exit 1
exit 0
