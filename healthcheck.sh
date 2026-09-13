#!/bin/bash
# Docker HEALTHCHECK probe for Koha.
#
# Exercise both the OPAC and staff intranet through Apache/Plack. The shared
# probe keeps cookies between checks so monitoring does not create an unbounded
# stream of anonymous Koha sessions.

set -u

OPACPORT="${OPACPORT:-80}"
INTRAPORT="${INTRAPORT:-8080}"

/docker/http-probe.sh "$OPACPORT" /run/koha-health/docker-opac.cookies || exit 1
/docker/http-probe.sh "$INTRAPORT" /run/koha-health/docker-intranet.cookies || exit 1
exit 0
