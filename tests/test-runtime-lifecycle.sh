#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Exercise the cleanup function which neutralises koha-create's service-starting
# side effects before schema upgrade and the container's own runtime startup.
eval "$(sed -n '/^stop_koha_create_services () {$/,/^}$/p' "$ROOT/entrypoint.sh")"

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export LIBRARY_NAME=library
export MOCK_LOG="$tmp/calls.log"

for command in service koha-worker koha-indexer koha-zebra; do
    cat > "$tmp/bin/$command" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$MOCK_LOG"
EOF
    chmod +x "$tmp/bin/$command"
done

stop_koha_create_services >/dev/null

cat > "$tmp/expected.log" <<'EOF'
service apache2 stop
koha-worker --all-queues --stop library
koha-indexer --stop library
koha-zebra --stop library
EOF

cmp -s "$tmp/expected.log" "$MOCK_LOG" || {
    echo "Expected koha-create cleanup calls:" >&2
    cat "$tmp/expected.log" >&2
    echo "Actual calls:" >&2
    cat "$MOCK_LOG" >&2
    fail "koha-create service cleanup changed"
}

# Once koha-create has been quiesced, normal runtime startup should use start,
# not restart-as-idempotency-workaround semantics.
grep -F 'koha-indexer --start "$LIBRARY_NAME"' "$ROOT/entrypoint.sh" >/dev/null || fail "indexer is not started cleanly"
if grep -F 'koha-indexer --restart' "$ROOT/entrypoint.sh" >/dev/null; then
    fail "indexer restart workaround was reintroduced"
fi
grep -F 'koha-worker --start --queue default "$LIBRARY_NAME"' "$ROOT/entrypoint.sh" >/dev/null || fail "default worker is not started cleanly"
grep -F 'koha-worker --start --queue long_tasks "$LIBRARY_NAME"' "$ROOT/entrypoint.sh" >/dev/null || fail "long_tasks worker is not started cleanly"
if grep -F 'koha-worker --restart' "$ROOT/entrypoint.sh" >/dev/null; then
    fail "worker restart workaround was reintroduced"
fi

# Fresh database creation has the same koha-create side effects as --use-db and
# must quiesce them before continuing.
create_db_body=$(sed -n '/^create_db () {$/,/^}$/p' "$ROOT/entrypoint.sh")
printf '%s\n' "$create_db_body" | grep -A2 'koha-create --create-db' | grep -F 'stop_koha_create_services' >/dev/null || fail "fresh create does not quiesce koha-create services"

# Keep expected runtime log noise out of steady-state startup.
grep -F 'a2ensite "$LIBRARY_NAME" >/dev/null' "$ROOT/entrypoint.sh" >/dev/null || fail "a2ensite success output is not suppressed"
grep -F "'ServerName localhost'" "$ROOT/Dockerfile" >/dev/null || fail "global Apache ServerName is missing"

# Optional services should only be stopped when they are configured for the
# instance, avoiding normal-shutdown 'not running' errors.
for feature in elasticsearch z3950 sip; do
    grep -F "if instance_feature_enabled $feature; then" "$ROOT/runtime.sh" >/dev/null || fail "shutdown does not gate $feature by instance configuration"
done

echo "runtime lifecycle tests: OK"
