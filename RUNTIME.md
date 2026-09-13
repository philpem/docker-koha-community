# Container runtime, maintenance and upgrades

This image is intended to behave as a self-contained Koha installation while
keeping MariaDB and memcached external. It therefore starts the runtime services
and periodic maintenance normally expected by the Debian `koha-common` package,
rather than requiring a host cron job or other external scheduler.

## Runtime services

The container starts and manages:

- Apache in the foreground for the OPAC and staff interface.
- Koha Plack/Starman.
- Zebra and the Koha indexer.
- Koha background workers for the `default` and `long_tasks` queues.
- Debian cron plus anacron, so the cron definitions shipped by `koha-common`
  remain the source of truth for scheduled Koha maintenance.
- The in-container HTTP watchdog.

`tini` is PID 1. A small runtime supervisor handles SIGTERM/SIGINT and performs
an ordered shutdown of Apache, cron, the workers, indexer, Zebra and Plack.

The following opt-out variables are available for unusual deployments:

- `KOHA_CRON_ENABLED=no`
- `KOHA_WORKERS_ENABLED=no`
- `WATCHDOG_ENABLED=no`

They all default to `yes`.

## Scheduled Koha maintenance

The image deliberately runs the cron jobs installed by `koha-common` instead of
copying individual Koha maintenance commands into Docker-specific scripts. This
means housekeeping such as session/database cleanup and message processing
tracks the installed Koha package automatically.

Anacron is started at container startup to catch up daily/weekly/monthly work
which was missed while the container was stopped.

## Health checks and watchdog

Docker HEALTHCHECK and the watchdog both exercise the real Koha application
through Apache/Plack. Their HTTP requests use the configured virtual host but
resolve it to `127.0.0.1`, and they keep separate cookie jars under `/run`.

The cookie jars are important: a stateless request to the Koha application root
can create a new anonymous Koha session. Reusing cookies prevents monitoring
from growing the `sessions` table indefinitely.

Only HTTP 2xx and 3xx responses count as healthy. Connection failures and 4xx/5xx
responses fail the probe.

## Persistent Docker state

The existing `/var/lib/koha` volume remains the only required Koha data volume.
The image stores its own state under:

```
/var/lib/koha/.docker-state/
    version
    koha-package-version
```

The state format is versioned independently of Koha itself. An image refuses to
start if it sees a state schema newer than it understands.

### Migration from older images

Older versions of this image stored only:

```
/var/lib/koha/<instance>/configured
```

If that marker exists and `.docker-state/version` does not, the installation is
recognised as state schema v1 and automatically migrated to v2. Existing
Compose environment variables and volume mappings do not need to change.

The v1 -> v2 migration:

1. creates the Docker state directory;
2. creates persistent Koha backup storage under `/var/lib/koha/backups`;
3. points the package-standard `/var/spool/koha` location at that persistent
   backup directory;
4. atomically records state schema v2.

## Koha upgrades

The image records the Koha package version only after schema migration has
completed successfully.

When the package version changes, startup performs the following sequence:

1. reconnect the existing Koha instance to the external database;
2. take a `koha-dump --exclude-indexes --exclude-logs` pre-upgrade backup;
3. run `koha-upgrade-schema`;
4. refuse to start Koha if schema migration fails;
5. atomically record the successfully migrated package version.

`KOHA_PRE_UPGRADE_BACKUP=no` disables the automatic pre-upgrade dump.
`KOHA_AUTO_UPGRADE_SCHEMA=no` retains the older manual-upgrade behaviour; when
used, a new package version is intentionally not recorded as successfully
migrated.

The Dockerfile defaults to the Koha `26.05` repository series rather than the
moving `stable` alias. Point/security updates within 26.05 are therefore picked
up by rebuilds, while changing to a later Koha release series is an explicit
source change which can be reviewed and backed up first.

## Backups

Koha's package-standard backup path `/var/spool/koha` is redirected into:

```
/var/lib/koha/backups
```

so backups produced by Koha's packaged jobs and the pre-upgrade backup survive
container recreation using the existing `/var/lib/koha` volume.

These backups complement rather than replace independent database/volume
backups performed by the deployment host.

## Database credentials and secrets

`DB_ROOT_PASSWORD` remains supported for compatibility.

For Docker secrets or other mounted secret files, use:

```
DB_ROOT_PASSWORD_FILE=/run/secrets/koha_db_root_password
```

Do not set both variables at once.

The generated `/etc/mysql/koha-common.cnf` is mode `0600` and is used as the
MariaDB client defaults file, avoiding repeated root passwords in command-line
arguments. Initial external-database access is configured using MariaDB account
DDL rather than direct modification of the `mysql.user` privilege table.

## Database release policy

The example Compose file pins MariaDB to the `12.3` release series rather than
the moving `lts` alias. Patch releases can therefore be pulled normally, while
a future LTS major-version transition is deliberate and reviewable.
