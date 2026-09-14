#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

export MARC003_XSLT_TEMPLATE="$ROOT/templates/add-marc003.xsl.in"
export MARC003_XSLT_OUTPUT_DIR="$tmp/xslt"
mkdir -p "$MARC003_XSLT_OUTPUT_DIR"

# A stale generated file should disappear when the requested set is committed.
printf 'stale\n' > "$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-OldCode.xsl"

export KOHA_MARC003_XSLT_CODES='UkOxU,DLC'
export KOHA_MARC003_XSLT_CODES_APPEND='DLC, DE-604'
bash "$ROOT/generate-marc003-xslts.sh" >/dev/null

for code in UkOxU DLC DE-604; do
    file="$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-${code}.xsl"
    [ -f "$file" ] || fail "missing generated stylesheet for $code"
    grep -F ">${code}</marc:controlfield>" "$file" >/dev/null || fail "stylesheet for $code does not contain its 003 value"
    if grep -F '${MARC003_CODE}' "$file" >/dev/null; then
        fail "stylesheet for $code still contains the template variable"
    fi
done

[ ! -e "$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-OldCode.xsl" ] || fail "stale generated stylesheet was not removed"
[ "$(find "$MARC003_XSLT_OUTPUT_DIR" -maxdepth 1 -name 'GeneratedAdd003-*.xsl' | wc -l)" -eq 3 ] || fail "duplicate identifiers produced duplicate output"

# Invalid input is rejected before the existing valid generated set is touched.
before=$(sha256sum "$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-DLC.xsl" | cut -d' ' -f1)
export KOHA_MARC003_XSLT_CODES='DLC,bad/code'
unset KOHA_MARC003_XSLT_CODES_APPEND
if bash "$ROOT/generate-marc003-xslts.sh" >/dev/null 2>&1; then
    fail "invalid identifier was accepted"
fi
after=$(sha256sum "$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-DLC.xsl" | cut -d' ' -f1)
[ "$before" = "$after" ] || fail "invalid configuration modified the previous generated set"

# An explicitly empty base list disables the image defaults. This is distinct
# from an unset variable, which selects the built-in default list.
export KOHA_MARC003_XSLT_CODES=''
export KOHA_MARC003_XSLT_CODES_APPEND=''
bash "$ROOT/generate-marc003-xslts.sh" >/dev/null
if find "$MARC003_XSLT_OUTPUT_DIR" -maxdepth 1 -name 'GeneratedAdd003-*.xsl' | grep -q .; then
    fail "empty configured list did not remove generated stylesheets"
fi

# Unset means use the built-in defaults. Check both a conventional MARC code
# and an ISIL identifier containing digits.
unset KOHA_MARC003_XSLT_CODES KOHA_MARC003_XSLT_CODES_APPEND
bash "$ROOT/generate-marc003-xslts.sh" >/dev/null
[ -f "$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-UkOxU.xsl" ] || fail "default MARC code was not generated"
[ -f "$MARC003_XSLT_OUTPUT_DIR/GeneratedAdd003-DE-604.xsl" ] || fail "default ISIL identifier was not generated"

echo "MARC 003 XSLT tests: OK"
