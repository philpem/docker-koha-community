#!/bin/bash
# Deep Koha application probe.
#
# This intentionally requests the real OPAC/staff application root and keeps a
# cookie jar so repeated probes reuse a Koha session. Normal container health
# and watchdog checks use /healthz instead; this script remains available for
# less-frequent functional checks which exercise normal Koha request handling.

set -u

port="${1:?usage: http-probe.sh PORT COOKIE_JAR}"
cookie_jar="${2:?usage: http-probe.sh PORT COOKIE_JAR}"
timeout="${HEALTHCHECK_TIMEOUT:-${WATCHDOG_HTTP_TIMEOUT:-10}}"

OPACPORT="${OPACPORT:-80}"
INTRAPORT="${INTRAPORT:-8080}"
LIBRARY_NAME="${LIBRARY_NAME:-defaultlibraryname}"
DOMAIN="${DOMAIN:-}"
OPACPREFIX="${OPACPREFIX:-}"
OPACSUFFIX="${OPACSUFFIX:-}"
INTRAPREFIX="${INTRAPREFIX:-}"
INTRASUFFIX="${INTRASUFFIX:-}"

if [ -n "$DOMAIN" ]; then
    if [ "$port" = "$OPACPORT" ]; then
        host="${OPACPREFIX}${OPACSUFFIX}${DOMAIN}"
    elif [ "$port" = "$INTRAPORT" ]; then
        host="${INTRAPREFIX}${INTRASUFFIX}${DOMAIN}"
    else
        echo "Unknown Koha HTTP port: $port" >&2
        exit 1
    fi
else
    host="$LIBRARY_NAME"
fi

mkdir -p "$(dirname "$cookie_jar")"

curl_args=(
    --silent
    --show-error
    --output /dev/null
    --write-out '%{http_code}'
    --max-time "$timeout"
    --location
    --max-redirs 3
    --cookie "$cookie_jar"
    --cookie-jar "$cookie_jar"
    --resolve "${host}:${port}:127.0.0.1"
    "http://${host}:${port}/"
)

if ! code=$(curl "${curl_args[@]}" 2>/dev/null); then
    exit 1
fi

case "$code" in
    2??|3??) exit 0 ;;
    *)       exit 1 ;;
esac
