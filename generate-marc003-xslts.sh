#!/bin/bash
# Generate source-specific MARC 003 transforms for Koha Z39.50/SRU targets.
#
# Koha associates an XSLT filename with each target, but does not pass target
# parameters into the stylesheet. Generate the small per-agency stylesheets at
# container startup from one maintained template instead of carrying duplicate
# XSLT source files in the image.

set -Eeuo pipefail

DEFAULT_MARC003_XSLT_CODES="CaAENA,DE-604,StEdNL,WlAbNL,UkBU,UkOxU,DLC"
TEMPLATE="${MARC003_XSLT_TEMPLATE:-/docker/templates/add-marc003.xsl.in}"
OUTPUT_DIR="${MARC003_XSLT_OUTPUT_DIR:-/usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/xslt}"
BASE_CODES="${KOHA_MARC003_XSLT_CODES-$DEFAULT_MARC003_XSLT_CODES}"
APPEND_CODES="${KOHA_MARC003_XSLT_CODES_APPEND-}"

if [ ! -r "$TEMPLATE" ]; then
    echo "ERROR: MARC 003 XSLT template is not readable: $TEMPLATE" >&2
    exit 1
fi

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

combined="$BASE_CODES"
if [ -n "$APPEND_CODES" ]; then
    combined="${combined:+${combined},}${APPEND_CODES}"
fi

# Parse, validate and deduplicate the complete list before touching the existing
# generated files. A typo in an environment variable therefore cannot destroy a
# previously valid generated set and leave Koha targets pointing at nothing.
declare -a codes=()
declare -A seen=()
IFS=',' read -r -a raw_codes <<< "$combined"
for raw_code in "${raw_codes[@]}"; do
    code=$(trim "$raw_code")
    [ -z "$code" ] && continue

    # MARC organization codes are normally alphabetic with optional dashes;
    # ISIL identifiers are also valid in MARC organization-code fields and may
    # contain digits (for example DE-604). Restrict to a filename/XML-safe
    # superset covering both forms.
    if [[ ! "$code" =~ ^[A-Za-z0-9-]+$ ]]; then
        echo "ERROR: invalid MARC 003 identifier '$code' (allowed: A-Z, a-z, 0-9, -)" >&2
        exit 1
    fi

    if [ -z "${seen[$code]:-}" ]; then
        seen[$code]=1
        codes+=("$code")
    fi
done

mkdir -p "$OUTPUT_DIR"
tmpdir=$(mktemp -d "$OUTPUT_DIR/.marc003-xslt.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

for code in "${codes[@]}"; do
    output="$tmpdir/GeneratedAdd003-${code}.xsl"
    MARC003_CODE="$code" envsubst '${MARC003_CODE}' < "$TEMPLATE" > "$output"
    chmod 0644 "$output"
done

# Only remove files owned by this generator. Commit the newly generated set only
# after every requested stylesheet was rendered successfully.
rm -f "$OUTPUT_DIR"/GeneratedAdd003-*.xsl
for code in "${codes[@]}"; do
    mv "$tmpdir/GeneratedAdd003-${code}.xsl" "$OUTPUT_DIR/"
done

if [ "${#codes[@]}" -eq 0 ]; then
    echo "*** MARC 003 XSLT generation disabled (no identifiers configured)"
else
    echo "*** Generated MARC 003 Z39.50/SRU transforms:"
    for code in "${codes[@]}"; do
        echo "***   $code -> GeneratedAdd003-${code}.xsl"
    done
fi
