#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Load only reconnect_db() from the entrypoint so the test exercises the actual
# production function without running the rest of container startup.
eval "$(sed -n '/^reconnect_db () {$/,/^}$/p' "$ROOT/entrypoint.sh")"

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export LIBRARY_NAME=library
export DB_ROOT_PASSWORD=secret
export DB_HOST=koha-db
export MOCK_LOG="$tmp/koha-create.log"
export MOCK_PASSWD_COPY="$tmp/passwd-file"

cat > "$tmp/bin/getent" <<'EOF'
#!/bin/bash
case "$1" in
    passwd) [ "${MOCK_USER_EXISTS:-no}" = yes ] ;;
    group)  [ "${MOCK_GROUP_EXISTS:-no}" = yes ] ;;
    *) exit 2 ;;
esac
EOF

cat > "$tmp/bin/koha-list" <<'EOF'
#!/bin/bash
if [ "${MOCK_SITE_EXISTS:-no}" = yes ]; then
    printf '%s\n' "$LIBRARY_NAME"
fi
EOF

cat > "$tmp/bin/koha-create" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG"
passwd_file=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = --passwdfile ]; then
        passwd_file="$2"
        break
    fi
    shift
done
[ -n "$passwd_file" ] || exit 90
cp "$passwd_file" "$MOCK_PASSWD_COPY"
exit "${MOCK_KOHA_CREATE_STATUS:-0}"
EOF

chmod +x "$tmp/bin/getent" "$tmp/bin/koha-list" "$tmp/bin/koha-create"

reset_mocks() {
    export MOCK_USER_EXISTS=no
    export MOCK_GROUP_EXISTS=no
    export MOCK_SITE_EXISTS=no
    export MOCK_KOHA_CREATE_STATUS=0
    rm -f "$MOCK_LOG" "$MOCK_PASSWD_COPY"
}

# Ordinary restart: all container-local instance state exists. Reconnect must be
# a no-op; koha-create --use-db would fail because the Unix user already exists.
reset_mocks
export MOCK_USER_EXISTS=yes
export MOCK_GROUP_EXISTS=yes
export MOCK_SITE_EXISTS=yes
reconnect_db
[ ! -e "$MOCK_LOG" ] || fail "ordinary restart invoked koha-create"

# Container recreation: persistent data says the instance is configured, but
# /etc/koha and the Unix account came from the old writable container layer and
# are gone. Recreate that local state against the existing database.
reset_mocks
reconnect_db
[ "$(wc -l < "$MOCK_LOG")" -eq 1 ] || fail "container recreation did not invoke koha-create exactly once"
grep -Fx -- '--use-db library --passwdfile ' "$MOCK_LOG" >/dev/null 2>&1 && fail "passwdfile path unexpectedly empty"
grep -F -- '--use-db library --passwdfile ' "$MOCK_LOG" >/dev/null || fail "koha-create was called with the wrong arguments"
[ "$(cat "$MOCK_PASSWD_COPY")" = 'library:root:secret:koha_library:koha-db' ] || fail "passwd file contents are wrong"

# A half-present local instance should not be handed to koha-create: it would
# either fail with 'User ... already exists' or risk masking damaged state.
reset_mocks
export MOCK_USER_EXISTS=yes
if reconnect_db 2>/dev/null; then
    fail "partial local state was accepted"
fi
[ ! -e "$MOCK_LOG" ] || fail "partial local state invoked koha-create"

# Real koha-create failures must remain fatal under strict startup handling.
reset_mocks
export MOCK_KOHA_CREATE_STATUS=23
if reconnect_db 2>/dev/null; then
    fail "koha-create failure was ignored"
fi
[ -e "$MOCK_LOG" ] || fail "koha-create failure test did not invoke koha-create"

echo "reconnect DB tests: OK"
