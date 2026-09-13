#!/bin/bash
# Persistent container-state management and upgrade helpers.
#
# User-facing Koha configuration remains environment-variable based. This file
# versions only the image's own persistent layout under /var/lib/koha so future
# migrations can be explicit and atomic.

DOCKER_STATE_SCHEMA=2
DOCKER_STATE_DIR=/var/lib/koha/.docker-state
DOCKER_STATE_VERSION_FILE="$DOCKER_STATE_DIR/version"
DOCKER_KOHA_VERSION_FILE="$DOCKER_STATE_DIR/koha-package-version"
DOCKER_BACKUP_DIR=/var/lib/koha/backups

atomic_write() {
    local destination="$1"
    local value="$2"
    local tmp

    mkdir -p "$(dirname "$destination")"
    tmp="${destination}.tmp.$$"
    printf '%s\n' "$value" > "$tmp"
    mv -f "$tmp" "$destination"
}

prepare_backup_layout() {
    mkdir -p "$DOCKER_BACKUP_DIR/$LIBRARY_NAME"

    # koha-dump and koha-run-backups use /var/spool/koha by default. Point
    # that package-standard path into the already-persistent /var/lib/koha
    # volume. Preserve anything an older image may have left in the image-local
    # spool before replacing it.
    if [ ! -L /var/spool/koha ]; then
        if [ -d /var/spool/koha ]; then
            cp -an /var/spool/koha/. "$DOCKER_BACKUP_DIR/" 2>/dev/null || true
            rm -rf /var/spool/koha
        elif [ -e /var/spool/koha ]; then
            rm -f /var/spool/koha
        fi
        ln -s "$DOCKER_BACKUP_DIR" /var/spool/koha
    fi
}

migrate_persistent_state() {
    local version

    mkdir -p "$DOCKER_STATE_DIR"

    if [ -f "$DOCKER_STATE_VERSION_FILE" ]; then
        version=$(cat "$DOCKER_STATE_VERSION_FILE")
    elif [ -f "/var/lib/koha/${LIBRARY_NAME}/configured" ]; then
        # Legacy images persisted only the per-instance 'configured' marker.
        version=1
    else
        # A fresh installation is created directly in the current layout.
        version=$DOCKER_STATE_SCHEMA
    fi

    case "$version" in
        1)
            echo "*** Migrating Docker persistent state v1 -> v2"
            prepare_backup_layout
            atomic_write "$DOCKER_STATE_VERSION_FILE" 2
            version=2
            ;;
        2)
            prepare_backup_layout
            ;;
        *)
            if [ "$version" -gt "$DOCKER_STATE_SCHEMA" ] 2>/dev/null; then
                echo "ERROR: persistent state schema $version is newer than this image supports ($DOCKER_STATE_SCHEMA)" >&2
            else
                echo "ERROR: unsupported persistent state schema '$version'" >&2
            fi
            return 1
            ;;
    esac

    # Fresh installs did not need a migration, but still need the marker.
    if [ ! -f "$DOCKER_STATE_VERSION_FILE" ]; then
        atomic_write "$DOCKER_STATE_VERSION_FILE" "$DOCKER_STATE_SCHEMA"
    fi
}

current_koha_package_version() {
    dpkg-query -W -f='${Version}' koha-common
}

record_koha_package_version() {
    atomic_write "$DOCKER_KOHA_VERSION_FILE" "$(current_koha_package_version)"
}

previous_koha_package_version() {
    if [ -f "$DOCKER_KOHA_VERSION_FILE" ]; then
        cat "$DOCKER_KOHA_VERSION_FILE"
    else
        printf '%s\n' unknown
    fi
}

pre_upgrade_backup() {
    local previous="$1"
    local current="$2"

    if [ "${KOHA_PRE_UPGRADE_BACKUP:-yes}" != "yes" ]; then
        echo "*** Pre-upgrade Koha backup disabled via KOHA_PRE_UPGRADE_BACKUP"
        return 0
    fi

    echo "*** Backing up Koha before package transition ${previous} -> ${current}"
    mkdir -p "$DOCKER_BACKUP_DIR/$LIBRARY_NAME"
    koha-dump --exclude-indexes --exclude-logs "$LIBRARY_NAME"
}
