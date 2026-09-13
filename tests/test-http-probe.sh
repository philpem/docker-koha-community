#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$MOCK_CURL_LOG"
printf '%s' "${MOCK_CURL_CODE:-200}"
exit "${MOCK_CURL_EXIT:-0}"
EOF
chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH"
export MOCK_CURL_LOG="$tmp/curl-args"
export DOMAIN=.example.test
export OPACPREFIX=opac
export INTRAPREFIX=staff
export OPACPORT=8080
export INTRAPORT=8081

cookie="$tmp/opac.cookies"

MOCK_CURL_CODE=200 MOCK_CURL_EXIT=0 bash "$ROOT/http-probe.sh" 8080 "$cookie" || fail "HTTP 200 was not accepted"
grep -Fx -- '--cookie' "$MOCK_CURL_LOG" >/dev/null || fail "cookie input option missing"
grep -Fx -- '--cookie-jar' "$MOCK_CURL_LOG" >/dev/null || fail "cookie output option missing"
grep -Fx -- "$cookie" "$MOCK_CURL_LOG" >/dev/null || fail "cookie jar path missing"
grep -Fx -- '--resolve' "$MOCK_CURL_LOG" >/dev/null || fail "local virtual-host resolve missing"
grep -Fx -- 'opac.example.test:8080:127.0.0.1' "$MOCK_CURL_LOG" >/dev/null || fail "OPAC virtual host resolve is incorrect"

MOCK_CURL_CODE=302 MOCK_CURL_EXIT=0 bash "$ROOT/http-probe.sh" 8080 "$cookie" || fail "HTTP redirect was not accepted"

if MOCK_CURL_CODE=500 MOCK_CURL_EXIT=0 bash "$ROOT/http-probe.sh" 8080 "$cookie"; then
    fail "HTTP 500 was accepted"
fi

if MOCK_CURL_CODE=000 MOCK_CURL_EXIT=7 bash "$ROOT/http-probe.sh" 8080 "$cookie"; then
    fail "curl transport failure was accepted"
fi

if MOCK_CURL_CODE=200 MOCK_CURL_EXIT=0 bash "$ROOT/http-probe.sh" 9999 "$cookie" 2>/dev/null; then
    fail "unknown Koha port was accepted"
fi

echo "HTTP probe tests: OK"
