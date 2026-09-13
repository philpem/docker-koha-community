#!/bin/bash
set -Eeuo pipefail

load_secret() {
    local name="$1"
    local file_name="${name}_FILE"
    local value="${!name-}"
    local file_value="${!file_name-}"

    if [ -n "$value" ] && [ -n "$file_value" ]; then
        echo "ERROR: set either $name or $file_name, not both" >&2
        exit 1
    fi
    if [ -n "$file_value" ]; then
        if [ ! -r "$file_value" ]; then
            echo "ERROR: cannot read $file_name path: $file_value" >&2
            exit 1
        fi
        printf -v "$name" '%s' "$(cat "$file_value")"
        export "$name"
    fi
}

load_secret DB_ROOT_PASSWORD
: "${DB_HOST:?DB_HOST must be set}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD or DB_ROOT_PASSWORD_FILE must be set}"
export DB_HOST DB_ROOT_PASSWORD

# Default values for environment variables
export DB_PORT="${DB_PORT:-3306}"
export DOMAIN="${DOMAIN:-}"
export INTRAPORT="${INTRAPORT:-8080}"
export INTRAPREFIX="${INTRAPREFIX:-}"
export INTRASUFFIX="${INTRASUFFIX:-}"
export LIBRARY_NAME="${LIBRARY_NAME:-defaultlibraryname}"
export MEMCACHED_PREFIX="${MEMCACHED_PREFIX:-koha_}"
export MEMCACHED_SERVERS="${MEMCACHED_SERVERS:-memcached:11211}"
export OPACPORT="${OPACPORT:-80}"
export OPACPREFIX="${OPACPREFIX:-}"
export OPACSUFFIX="${OPACSUFFIX:-}"
export SLEEP="${SLEEP:-3}"
export USE_MEMCACHED="${USE_MEMCACHED:-yes}"
export ZEBRA_MARC_FORMAT="${ZEBRA_MARC_FORMAT:-marc21}"
export ZEBRA_LANGUAGE="${ZEBRA_LANGUAGE:-en}"
export BIBLIOS_INDEXING_MODE="${BIBLIOS_INDEXING_MODE:-dom}"
export AUTHORITIES_INDEXING_MODE="${AUTHORITIES_INDEXING_MODE:-dom}"
export KOHA_TRANSLATE_LANGUAGES="${KOHA_TRANSLATE_LANGUAGES:-}"

# Persistent-layout migrations and Koha package-version tracking.
. /docker/state.sh

update_koha_sites () {
    echo "*** Modifying /etc/koha/koha-sites.conf"
    envsubst < /docker/templates/koha-sites.conf > /etc/koha/koha-sites.conf
}

update_httpd_listening_ports () {
    echo "*** Fixing apache2 listening ports"
    if [ "80" != "$INTRAPORT" ]; then
        grep -q "Listen $INTRAPORT" /etc/apache2/ports.conf || echo "Listen $INTRAPORT" >> /etc/apache2/ports.conf
    fi
    if [ "80" != "$OPACPORT" ] && [ "$INTRAPORT" != "$OPACPORT" ]; then
        grep -q "Listen $OPACPORT" /etc/apache2/ports.conf || echo "Listen $OPACPORT" >> /etc/apache2/ports.conf
    fi
}

update_koha_database_conf () {
    echo "*** Modifying /etc/mysql/koha-common.cnf"
    local old_umask
    old_umask=$(umask)
    umask 077
    envsubst < /docker/templates/koha-common.cnf > /etc/mysql/koha-common.cnf
    umask "$old_umask"
    chmod 600 /etc/mysql/koha-common.cnf
}

mysql_root() {
    mysql --defaults-extra-file=/etc/mysql/koha-common.cnf "$@"
}

mysqladmin_root() {
    mysqladmin --defaults-extra-file=/etc/mysql/koha-common.cnf "$@"
}

fix_database_permissions () {
    local user="koha_${LIBRARY_NAME}"
    local database="koha_${LIBRARY_NAME}"

    echo "*** Fixing database permissions to be able to use an external server"
    # TODO: restrict to the docker container private IP
    # TODO: investigate how to change hardcoded 'koha_' preffix in database name and username creatingg '/etc/koha/sites/${LIBRARY_NAME}/koha-conf.xml.in'
    # koha-create creates the account for localhost. RENAME USER preserves its
    # generated credentials without editing MariaDB's internal privilege tables.
    mysql_root -e "RENAME USER '${user}'@'localhost' TO '${user}'@'%'; GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${user}'@'%';"
}

log_database_credentials () {
    echo "===================================================="
    echo "IMPORTANT: credentials needed to post-installation through your browser"
    echo "Username: koha_$LIBRARY_NAME"
    echo "Password: type 'docker exec -ti $(hostname) koha-passwd $LIBRARY_NAME' to display it"
    echo "===================================================="
}

install_koha_translate_languages () {
    local -a languages

    if [ -z "$KOHA_TRANSLATE_LANGUAGES" ]; then
        return 0
    fi

    echo "*** Installing koha translate languages defined by KOHA_TRANSLATE_LANGUAGES"
    IFS=',' read -r -a languages <<< "$KOHA_TRANSLATE_LANGUAGES"
    for language in "${languages[@]}"; do
        koha-translate --install "$language"
    done
}

is_exists_db () {
    # TODO: fix hardcoded database name
    local database="koha_${LIBRARY_NAME}"
    [ "$(mysql_root -Nse "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${database}'")" -gt 0 ]
}

update_apache2_conf () {
    echo "*** Creating /etc/apache2/sites-available/${LIBRARY_NAME}.conf"
    if [ -n "$DOMAIN" ]
    then
        # Default script will always put 'InstanceName':
        # http://{INTRAPREFIX}{InstanceName}{INTRASUFFIX}{DOMAIN}:{INTRAPORT}
        # Below function does NOT covers all cases, but it works for a simple one:
        # OPAC => https://library.example.com
        # Intra => https://library.admin.example.com

        envsubst < /docker/templates/koha.conf > /etc/apache2/sites-available/${LIBRARY_NAME}.conf
    else
        # TODO1: understand why whith this new version the automatic generation of config file looks like not working, even thouth 'INTRAPORT' variable is good
        # TODO2: remove hardvoded values of 'templates/koha.conf' and unify it with 'templates/koha-no-domain.conf'
        envsubst < /docker/templates/koha-no-domain.conf > /etc/apache2/sites-available/${LIBRARY_NAME}.conf
    fi
    a2ensite ${LIBRARY_NAME}
}

reconnect_db () {
    local passwd_file
    passwd_file=$(mktemp)
    chmod 600 "$passwd_file"
    printf '%s\n' "$LIBRARY_NAME:root:$DB_ROOT_PASSWORD:koha_$LIBRARY_NAME:$DB_HOST" > "$passwd_file"
    if ! koha-create --use-db "$LIBRARY_NAME" --passwdfile "$passwd_file"; then
        rm -f "$passwd_file"
        return 1
    fi
    rm -f "$passwd_file"
}

upgrade_schema () {
    # Idempotent: if the DB schema matches the running Koha version this is a
    # no-op. When it doesn't (e.g. after a Koha image upgrade) it applies the
    # pending migrations so Plack workers can start cleanly instead of leaving
    # Apache returning 503 until somebody completes the web upgrade flow.
    local previous current
    previous=$(previous_koha_package_version)
    current=$(current_koha_package_version)

    if [ "${KOHA_AUTO_UPGRADE_SCHEMA:-yes}" != "yes" ]; then
        echo "*** Automatic schema upgrade disabled via KOHA_AUTO_UPGRADE_SCHEMA"
        if [ "$previous" != "$current" ]; then
            echo "*** WARNING: Koha package changed ${previous} -> ${current}; package version will not be recorded until schema upgrade succeeds"
        fi
        return 0
    fi

    if [ "$previous" != "$current" ]; then
        if ! pre_upgrade_backup "$previous" "$current"; then
            echo "ERROR: pre-upgrade Koha backup failed; refusing to migrate schema" >&2
            return 1
        fi
    fi

    echo "*** Running koha-upgrade-schema (no-op if already current)..."
    if ! koha-upgrade-schema "$LIBRARY_NAME"; then
        echo "ERROR: koha-upgrade-schema failed; refusing to start Koha" >&2
        return 1
    fi

    record_koha_package_version
}

create_db () {
    echo "*** Creating database..."
    while ! mysqladmin_root ping --silent; do
        echo "*** Database server still down. Waiting $SLEEP seconds until retry"
        sleep "$SLEEP"
    done
    if is_exists_db
    then
        echo "*** Database already exists"
        reconnect_db
        # Needed because 'koha-create' restarts apache and puts process in background"
        echo "*** Manual indexing is needed..."
        koha-rebuild-zebra -v --full "$LIBRARY_NAME"
    else
        echo "*** koha-create with db"
        koha-create --create-db "$LIBRARY_NAME"
        # Needed because 'koha-create' restarts apache and puts process in background"
        fix_database_permissions
    fi
}

enable_plack () {
    echo "*** Enabling and starting plack..."
    koha-plack --enable ${LIBRARY_NAME}
}

start_watchdog() {
    if [ "${WATCHDOG_ENABLED:-yes}" = "yes" ]; then
        echo "*** Starting watchdog..."
        /docker/watchdog.sh &
    else
        echo "*** Watchdog disabled via WATCHDOG_ENABLED"
    fi
}

start_workers() {
    if [ "${KOHA_WORKERS_ENABLED:-yes}" = "yes" ]; then
        echo "*** Starting Koha background workers..."
        # Use explicit queues for compatibility with Koha versions predating
        # koha-worker --all-queues.
        koha-worker --restart --queue default "$LIBRARY_NAME"
        koha-worker --restart --queue long_tasks "$LIBRARY_NAME"
    else
        echo "*** Koha background workers disabled via KOHA_WORKERS_ENABLED"
    fi
}

start_scheduler() {
    if [ "${KOHA_CRON_ENABLED:-yes}" = "yes" ]; then
        echo "*** Starting cron for packaged Koha maintenance jobs..."
        cron
        # Cron runs future jobs. anacron catches up daily/weekly/monthly jobs
        # that were missed while the container was stopped.
        echo "*** Starting anacron catch-up..."
        anacron -s &
    else
        echo "*** Koha scheduler disabled via KOHA_CRON_ENABLED"
    fi
}

print_startup_summary() {
    echo "===================================================="
    echo "Koha container startup"
    echo "  instance:       $LIBRARY_NAME"
    echo "  Koha package:   $(current_koha_package_version)"
    echo "  state schema:   $(cat "$DOCKER_STATE_VERSION_FILE")"
    echo "  database:       ${DB_HOST}:${DB_PORT}"
    echo "  memcached:      $MEMCACHED_SERVERS"
    echo "  cron/anacron:   ${KOHA_CRON_ENABLED:-yes}"
    echo "  workers:        ${KOHA_WORKERS_ENABLED:-yes}"
    echo "  watchdog:       ${WATCHDOG_ENABLED:-yes}"
    echo "  backup path:    $DOCKER_BACKUP_DIR"
    echo "===================================================="
}

start_koha() {
    echo "*** Starting koha with plack..."
    koha-plack --start $LIBRARY_NAME
    # koha-create (run by reconnect_db) already starts the indexer, so use
    # --restart here to avoid the "already running: failed!" warning on
    # the second invocation while still working on a fresh boot.
    echo "*** Starting indexer..."
    koha-indexer --restart $LIBRARY_NAME
    echo "*** Starting zebra..."
    koha-zebra --start $LIBRARY_NAME
    start_workers
    start_scheduler
    start_watchdog
    echo "*** Starting apache in foreground..."
    apachectl -D FOREGROUND
}

update_koha_database_conf
update_koha_sites
update_httpd_listening_ports

# Migrate image-owned persistent layout before using it. Existing installations
# without a state marker are recognised as legacy v1 and migrated in place.
if ! migrate_persistent_state; then
    exit 1
fi
print_startup_summary

# 1st docker container execution
if [ ! -f /var/lib/koha/${LIBRARY_NAME}/configured ]; then
    echo "*** Running first time configuration..."
    create_db
    install_koha_translate_languages
    log_database_credentials
    date > /var/lib/koha/${LIBRARY_NAME}/configured
    record_koha_package_version
else
    # 2nd+ executions
    echo "*** Already configured, reconnecting to database..."
    reconnect_db
    upgrade_schema
fi

enable_plack
update_apache2_conf

# koha-create starts apache as a side effect; stop it so we can
# relaunch in the foreground with start_koha
service apache2 stop 2>/dev/null || true
start_koha
