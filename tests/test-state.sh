#!/bin/bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

test_legacy_migration() (
    set -Eeuo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    export LIBRARY_NAME=library
    export DOCKER_KOHA_DATA_DIR="$tmp/data"
    export DOCKER_KOHA_SPOOL_DIR="$tmp/spool/koha"

    mkdir -p "$DOCKER_KOHA_DATA_DIR/$LIBRARY_NAME" "$DOCKER_KOHA_SPOOL_DIR"
    touch "$DOCKER_KOHA_DATA_DIR/$LIBRARY_NAME/configured"
    printf 'legacy backup\n' > "$DOCKER_KOHA_SPOOL_DIR/legacy.txt"

    . "$ROOT/state.sh"
    migrate_persistent_state

    [ "$(cat "$DOCKER_STATE_VERSION_FILE")" = 2 ] || fail "legacy install was not migrated to schema v2"
    [ -L "$DOCKER_KOHA_SPOOL_DIR" ] || fail "Koha spool was not replaced by a symlink"
    [ "$(readlink "$DOCKER_KOHA_SPOOL_DIR")" = "$DOCKER_BACKUP_DIR" ] || fail "Koha spool points at the wrong backup directory"
    [ -f "$DOCKER_BACKUP_DIR/legacy.txt" ] || fail "legacy spool contents were not preserved"
)

test_fresh_state() (
    set -Eeuo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    export LIBRARY_NAME=library
    export DOCKER_KOHA_DATA_DIR="$tmp/data"
    export DOCKER_KOHA_SPOOL_DIR="$tmp/spool/koha"

    . "$ROOT/state.sh"
    migrate_persistent_state

    [ "$(cat "$DOCKER_STATE_VERSION_FILE")" = 2 ] || fail "fresh install did not get schema v2"
    [ -L "$DOCKER_KOHA_SPOOL_DIR" ] || fail "fresh install did not create persistent backup symlink"
)

test_future_state_rejected() (
    set -Eeuo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    export LIBRARY_NAME=library
    export DOCKER_KOHA_DATA_DIR="$tmp/data"
    export DOCKER_KOHA_SPOOL_DIR="$tmp/spool/koha"

    mkdir -p "$DOCKER_KOHA_DATA_DIR/.docker-state"
    printf '99\n' > "$DOCKER_KOHA_DATA_DIR/.docker-state/version"

    . "$ROOT/state.sh"
    if migrate_persistent_state 2>/dev/null; then
        fail "future state schema was accepted"
    fi
)

test_invalid_state_rejected() (
    set -Eeuo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    export LIBRARY_NAME=library
    export DOCKER_KOHA_DATA_DIR="$tmp/data"
    export DOCKER_KOHA_SPOOL_DIR="$tmp/spool/koha"

    mkdir -p "$DOCKER_KOHA_DATA_DIR/.docker-state"
    printf 'not-a-version\n' > "$DOCKER_KOHA_DATA_DIR/.docker-state/version"

    . "$ROOT/state.sh"
    if migrate_persistent_state 2>/dev/null; then
        fail "invalid state schema was accepted"
    fi
)

test_legacy_migration
test_fresh_state
test_future_state_rejected
test_invalid_state_rejected

echo "state migration tests: OK"
