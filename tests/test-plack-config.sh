#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

for template in \
    "$ROOT/templates/koha.conf" \
    "$ROOT/templates/koha-no-domain.conf"
do
    grep -Eq '^[[:space:]]*Include /etc/koha/apache-shared-opac-plack\.conf[[:space:]]*$' "$template" || \
        fail "$(basename "$template") does not enable OPAC Plack"
    grep -Eq '^[[:space:]]*Include /etc/koha/apache-shared-intranet-plack\.conf[[:space:]]*$' "$template" || \
        fail "$(basename "$template") does not enable intranet Plack"
done

# The Docker-owned Apache templates are authoritative for Plack enablement.
# Calling `koha-plack --enable` is not idempotent: upstream returns status 1
# when both interfaces are already enabled, which aborts this strict entrypoint.
if grep -Eq '^[[:space:]]*koha-plack[[:space:]]+--enable([[:space:]]|$)' "$ROOT/entrypoint.sh"; then
    fail "entrypoint still invokes non-idempotent koha-plack --enable"
fi

echo "Plack configuration tests: OK"
