#!/bin/bash
# Docker HEALTHCHECK probe for Koha.
#
# Exercise both Apache virtual hosts through the lightweight /healthz endpoint.
# This verifies Apache, proxying, a live Plack/Starman worker, Koha's Perl/config
# environment and database connectivity without creating Koha sessions.

set -u

OPACPORT="${OPACPORT:-80}"
INTRAPORT="${INTRAPORT:-8080}"

/docker/healthz-probe.sh "$OPACPORT" || exit 1
/docker/healthz-probe.sh "$INTRAPORT" || exit 1
exit 0
