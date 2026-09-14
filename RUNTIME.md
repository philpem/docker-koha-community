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
- SIP, the Z39.50 responder and the Elasticsearch indexer when those features
  are enabled for the Koha instance.

`tini` is PID 1. A small runtime supervisor handles SIGTERM/SIGINT and performs
an ordered shutdown of Apache, cron, the workers and Koha daemons. Optional
SIP, Z39.50 and Elasticsearch daemons are only stopped when they are configured
for the instance, avoiding misleading "not running" errors during normal
shutdown.

The following opt-out variables are available for unusual deployments:

- `KOHA_CRON_ENABLED=no`
- `KOHA_WORKERS_ENABLED=no`
- `WATCHDOG_ENABLED=no`

They all default to `yes`.

## Startup lifecycle

There are three distinct startup cases. The persistent `/var/lib/koha` volume
contains the Docker state marker and Koha application data, but the Koha Unix
account and `/etc/koha/sites/<instance>` configuration live in the container's
writable layer and therefore behave differently across a restart and a
recreation.

### Ordinary container restart

On an ordinary restart the container-local Unix account, group and Koha site
configuration are still present. Startup reuses that local instance and does
not run `koha-create --use-db` again.

The schema check then runs before any application daemons are started. With
`KOHA_AUTO_UPGRADE_SCHEMA=yes` this invokes `koha-upgrade-schema` on every
already-configured startup; when the schema is already current it is a no-op.

### Recreated container

When Docker recreates the container, the persistent `/var/lib/koha` state and
external MariaDB database remain, but the local Unix account and `/etc/koha`
instance configuration are absent. Startup detects this cleanly absent local
state and reconstructs it with:

```
koha-create --use-db <instance> --passwdfile <temporary-file>
```

Upstream `koha-create` starts Apache, Zebra, the background workers and the
indexer as side effects. Those services are immediately quiesced again before
schema migration or normal runtime startup. This prevents new Koha code or
workers from running against a database schema which may still need upgrading.

A partially present local instance -- for example, a Unix account without a
matching Koha site -- is treated as an error rather than being passed to
`koha-create`, because that state is ambiguous and `koha-create` is not
idempotent for an existing Unix account.

### First installation

A genuinely new installation uses `koha-create --create-db`. Its Apache, Zebra,
worker and indexer side effects are also quiesced immediately so the container
can take ownership of the ordered runtime startup itself.

After configuration and any required schema work, the container performs the
same managed startup sequence in all cases:

1. install the instance-specific Plack health wrapper;
2. write and enable the Docker-owned Apache site configuration;
3. ensure Koha runtime directories exist;
4. start Plack;
5. start the Koha indexer;
6. start Zebra;
7. start enabled optional SIP, Z39.50 and Elasticsearch services;
8. start the `default` and `long_tasks` background workers when enabled;
9. start cron and anacron when enabled;
10. start the watchdog when enabled;
11. run Apache in the foreground.

The Docker-owned Apache templates already enable Plack for the OPAC and staff
interfaces, so startup deliberately does not call `koha-plack --enable`.
Upstream treats "already enabled" as a non-zero result, which is unsuitable for
an idempotent strict-mode container startup.

## Scheduled Koha maintenance

The image deliberately runs the cron jobs installed by `koha-common` instead of
copying individual Koha maintenance commands into Docker-specific scripts. This
means housekeeping such as session/database cleanup and message processing
tracks the installed Koha package automatically.

Anacron is started at container startup to catch up daily/weekly/monthly work
which was missed while the container was stopped.

## Health checks and watchdog

Docker HEALTHCHECK and the watchdog use the session-free `/healthz` endpoint on
both Apache virtual hosts. The request exercises Apache, mod_proxy, the
Plack/Starman Unix socket, a live Koha worker, `C4::Context` and a `SELECT 1`
against MariaDB without entering Koha's normal session-handling path.

A healthy endpoint returns HTTP 200 with `ok`. A database check failure returns
HTTP 503 with `unhealthy`; the watchdog recognises that response as a
MariaDB-only problem and does not repeatedly restart a healthy Plack process.
Other transport, proxy or unexpected HTTP failures count as application-path
failures and can trigger the normal consecutive-failure Plack restart policy.

`http-probe.sh` remains available as a deeper functional probe of the real OPAC
or staff application root. It preserves a cookie jar so repeated deep probes
reuse a Koha session rather than creating an unbounded stream of anonymous
sessions. This is suitable for lower-frequency external monitoring when normal
page rendering should also be tested.

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

`/etc/koha` and the `<instance>-koha` Unix account are intentionally not part of
this persistent state. They are reused on an ordinary restart and reconstructed
from the persistent marker plus the existing external database when a container
is recreated, as described in [Startup lifecycle](#startup-lifecycle).

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

For an already-configured installation, startup performs the following sequence:

1. reuse the existing local Koha instance on an ordinary restart, or reconstruct
   its local Unix account and `/etc/koha` configuration when the container has
   been recreated;
2. if `koha-create` was required, immediately quiesce the Apache, Zebra, worker
   and indexer processes it starts as side effects;
3. when the recorded Koha package version has changed, take a
   `koha-dump --exclude-indexes --exclude-logs` pre-upgrade backup;
4. run `koha-upgrade-schema` before Plack, Zebra, workers or Apache are started
   by the container runtime;
5. refuse to start Koha if schema migration fails;
6. atomically record the successfully migrated package version;
7. perform the normal ordered runtime startup described above.

On an ordinary restart with an unchanged package version, the backup step is
skipped. `koha-upgrade-schema` still runs by default and simply reports that no
database change is required when the schema is already current.

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
