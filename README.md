# Koha Community Edition Docker container

This is an updated version of [Kedu SCCL's original version](https://github.com/Kedu-SCCL/docker-koha-community). Changes include:

  - Switch to later versions of MariaDB and Debian.
  - Koha versions from early 2025 need GD::Barcode 2.01 or later -- make sure this is available.
  - Fix the ordering of startup processes so Koha uses Memcached.
  - Add volumes to the compose script so data is stored outside of the containers.
  - Put the intranet and OPAC on different ports.
  - Fix population of the database when it's completely empty.
  - Auto-recovery: an in-container watchdog restarts Plack/Zebra/the indexer
    if they crash or get wedged, and a Docker `HEALTHCHECK` reports the
    container as unhealthy when the OPAC or staff intranet returns 502/503.

This can be used standalone to try out Koha, but if you want to deploy this you'll probably want to customise the `docker-compose.yml`.


# Original documentation

- [Introduction](#introduction)
- [For the impatients](#for-the-impatients)
- [Environment Variables](#environment-variables)
  - [DB_HOST](#DB_HOST)
  - [DB_ROOT_PASSWORD](#DB_ROOT_PASSWORD)
  - [DB_PORT](#DB_PORT)
  - [KOHA_TRANSLATE_LANGUAGES](#KOHA_TRANSLATE_LANGUAGES)
  - [LIBRARY_NAME](#LIBRARY_NAME)
  - [SLEEP](#SLEEP)
  - [DOMAIN](#DOMAIN)
  - [INTRAPORT](#INTRAPORT)
  - [INTRAPREFIX](#INTRAPREFIX)
  - [INTRASUFFIX](#INTRASUFFIX)
  - [OPACPORT](#OPACPORT)
  - [OPACPREFIX](#OPACPREFIX)
  - [OPACSUFFIX](#OPACSUFFIX)
- [Allowed volumes](#allowed-volumes)
- [Example with reverse proxy](#example-with-reverse-proxy)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

# Introduction

Koha 

[Koha community](https://wiki.koha-community.org/) with below features:

* Supports external database
* Supports multiple translation installations
* Internal and external (OPAC) URLs completely customizable
* External memcached server

# For the impatients

1. Start the containers

```
sudo docker-compose up -d --build --force-recreate
```

2. Get the username and password for the post-install part. See below entries in the docker compose output:

```
====================================================
IMPORTANT: credentials needed to post-installation through your browser
Username: koha_koha
Password: type 'docker exec -ti d21a7f723205 koha-passwd koha' to display it
====================================================
```

3. Point your browser to:

http://localhost:8080

And introduce the credentials annotated at step 3

4. Follow the steps in the browser. At one step you will create the admin credentials. Please annotate them for later use

5. Once you finished the post-install steps, you can login to:

Admin

http://localhost:8080

Public (OPAC)

http://localhost

In both cases the credentials are the ones annotated at step 5

# Environment Variables

## DB_HOST

Mandatory. Name of the database server. Should be reachable by koha container.

This image has been tested with mariadb server.

Example:

```
-e DB_HOST=koha-db
```

## DB_ROOT_PASSWORD

Mandatory. Password of "root" account of "DB_HOST" database server.

Example:

```
-e DB_ROOT_PASSWORD=secretpassword
```

## DB_PORT

Optional, if not provided set up to "3306".

Port where "DB_HOST" database server is listening.

Example:

```
-e DB_PORT=3307
```

## KOHA_TRANSLATE_LANGUAGES

Optional, if not provided set up to empty value.

Comma separated list of koha translations to be installed.

To get a full list of available translations:

1. Start the koha docker container

2. Connect to it (in this example the docker koha container is named "koha")

```
docker exec -ti koha bash
```

3. Get the list

```
koha-translate --list --available
```

Expected output similar to:

```
am-Ethi
ar-Arab
as-IN
az-AZ
be-BY
bg-Cyrl
bn-IN
ca-ES
cs-CZ
cy-GB
da-DK
de-CH
de-DE
el-GR
en-GB
en-NZ
eo
es-ES
eu
fa-Arab
fi-FI
fo-FO
fr-CA
fr-FR
ga
gd
gl
he-Hebr
hi
hr-HR
hu-HU
hy-Armn
ia
id-ID
iq-CA
is-IS
it-IT
iu-CA
ja-Jpan-JP
ka
km-KH
kn-Knda
ko-Kore-KP
ku-Arab
lo-Laoo
lv
mi-NZ
ml
mon
mr
ms-MY
my
nb-NO
ne-NE
nl-BE
nl-NL
nn-NO
oc
pbr
pl-PL
prs
pt-BR
pt-PT
ro-RO
ru-RU
rw-RW
sd-PK
sk-SK
sl-SI
sq-AL
sr-Cyrl
sv-SE
sw-KE
ta-LK
ta
tet
th-TH
tl-PH
tr-TR
tvl
uk-UA
ur-Arab
vi-VN
zh-Hans-CN
zh-Hant-TW
```

Example:

```
-e KOHA_TRANSLATE_LANGUAGES="ca-ES,es-ES"
```

## LIBRARY_NAME

Optional, if not provided set up to "defaultlibraryname".

String containing the library name, used by "koha-create --create-db" command.

Example:

```
-e LIBRARY_NAME=mylibrary
```

## SLEEP

Optional, if not provided set up to "3".

Time in seconds that the koha image is waiting on to retry connection to external database when installing product for the first time.

Example:

```
-e SLEEP=2
```

## DOMAIN

Optional, if not provided set up to empty value.

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

Example:

```
-e DOMAIN=.example.com
```

## INTRAPORT

Optional, if not provided set up to "8080".

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

```
Example:

```
-e INTRAPORT=80
```

## INTRAPREFIX

Optional, if not provided set up to empty value.

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

Example:

```
-e INTRAPREFIX=library
```

## INTRASUFFIX

Optional, if not provided set up to empty value.

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

Example:

```
-e INTRASUFFIX=.admin
```

## OPACPORT

Optional, if not provided set up to "80".

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

Example:

```
-e OPACPORT=80
```

## OPACPREFIX

Optional, if not provided set up to empty value.

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

Example:

```
-e OPACPREFIX=library
```

## OPACSUFFIX

Optional, if not provided set up to empty value.

String to build the internal and external (OPAC) URLs:

```
# OPAC:  http://<OPACPREFIX><OPACSUFFIX><DOMAIN>:<OPACPORT>
# STAFF: http://<INTRAPREFIX><INTRASUFFIX><DOMAIN>:<INTRAPORT>
```

WARNING: it dows not adds instance name between 'OPACPREFIX' and 'OPACSUFFIX'

Example:

```
-e OPACPREFIX=opac
```

# Auto-recovery

Apache runs in the foreground inside the container, but it depends on
several background services (Plack/Starman, Zebra, the indexer). If one
of those crashes the container stays "up" — Apache just starts returning
HTTP 503 to the user.

To recover automatically:

* `/docker/watchdog.sh` runs in the background. Every `WATCHDOG_INTERVAL`
  seconds it checks `koha-plack`, `koha-zebra` and `koha-indexer` and
  restarts any that aren't running. It also makes an HTTP request to the
  OPAC and intranet ports; if it gets 502/503/504 (or no response) for
  `WATCHDOG_HTTP_FAILURES` consecutive checks it restarts Plack.
* A Docker `HEALTHCHECK` probes the same ports so orchestrators can see
  when the container is unhealthy. Combine it with an external auto-heal
  tool (e.g. [willfarrell/autoheal](https://github.com/willfarrell/autoheal))
  or Kubernetes liveness probes if you want the whole container to be
  recreated when the watchdog can't recover on its own.

Tunable environment variables:

| Variable                  | Default | Description                                               |
| ------------------------- | ------- | --------------------------------------------------------- |
| `WATCHDOG_ENABLED`        | `yes`   | Set to anything else to disable the watchdog.             |
| `WATCHDOG_INTERVAL`       | `30`    | Seconds between checks.                                   |
| `WATCHDOG_HTTP_TIMEOUT`   | `10`    | Per-request timeout for HTTP probes.                      |
| `WATCHDOG_HTTP_FAILURES`  | `2`     | Consecutive HTTP failures before Plack is restarted.      |
| `HEALTHCHECK_TIMEOUT`     | `10`    | Per-request timeout for the Docker healthcheck.           |
| `KOHA_AUTO_UPGRADE_SCHEMA`| `yes`   | Run `koha-upgrade-schema` on startup. No-op if up to date.|

After a Koha image upgrade the database schema can lag behind the code,
which leaves Plack workers unable to start and Apache returning 503.
`koha-upgrade-schema` runs automatically on every start (in the
"already configured" path) so the migration happens before Plack comes
up. It's idempotent — when the DB is already current it just logs that
and exits.

# Allowed volumes

We recommend to map "/var/lib/koha".

Example:

```
-v ~/koha:/var/lib/koha
```

# Example with admin and OPAC listening on the same port

Below file has been provided:

```
docker-compose.yml.domain
```

# Troubleshooting

**TODO**

# Credits

Some ideas has been taken from [QuantumObject/docker-koha](https://github.com/QuantumObject/docker-koha)
