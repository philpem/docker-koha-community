# Koha needs libgd-barcode-perl >= 2.01. Debian stable (Trixie) ships only
# 2.00, but it carries every other Koha dependency -- including
# libauthen-cas-client-perl, which was autoremoved from testing/Forky in
# June 2026 (Debian bug #879564). So we base on stable and pull just
# libgd-barcode-perl from unstable (sid), which has 2.01.
FROM debian:trixie
LABEL maintainer="philpem@philpem.me.uk"

# Avoid debconf "unable to initialize frontend: Readline" warnings during build.
# ARG instead of ENV so the value doesn't leak into the running container.
ARG DEBIAN_FRONTEND=noninteractive

# https://koha-community.org/
ARG KOHA_VERSION=stable
ARG PKG_URL=https://debian.koha-community.org/koha

# Install Debian baseline packages.
# Koha needs libgd-barcode-perl >= 2.01, which stable (Trixie) doesn't ship
# (it has 2.00). Add unstable (sid) as a source, but pin it so ONLY
# libgd-barcode-perl is taken from it: the general '*' rule at priority 100
# keeps every other sid package below stable's default of 500, while the
# targeted rule at 990 lifts libgd-barcode-perl above stable so its 2.01 is
# preferred. The module is Architecture: all and depends only on packages
# already in stable, so nothing else upgrades from unstable.
RUN apt-get update && apt-get install -y \
  curl \
  wget \
  gnupg && \
  echo "deb http://deb.debian.org/debian sid main" > /etc/apt/sources.list.d/sid.list && \
  printf 'Package: *\nPin: release a=unstable\nPin-Priority: 100\n\nPackage: libgd-barcode-perl\nPin: release a=unstable\nPin-Priority: 990\n' > /etc/apt/preferences.d/99-sid && \
  apt-get update && \
  apt-get -y satisfy "libgd-barcode-perl (>= 2.01)" && \
  rm -rf /var/lib/apt/lists/*

# Set up the Koha repository and install it
RUN \
  if [ "${PKG_URL}" = "https://debian.koha-community.org/koha" ]; then \
    wget -q -O /etc/apt/trusted.gpg.d/koha.asc https://debian.koha-community.org/koha/gpg.asc ;  \
  fi ; \
  echo "deb ${PKG_URL} ${KOHA_VERSION} main" | tee /etc/apt/sources.list.d/koha.list ; \
  apt-get update && apt-get install -y \
    koha-common && \
  rm -rf /var/lib/apt/lists/*

# Enable some Apache modules and disable the default site
RUN a2enmod rewrite \
           headers \
           proxy_http \
           cgi \
    && a2dissite 000-default \
    && rm -R /var/www/html/

RUN mkdir /docker

COPY entrypoint.sh /docker/
COPY watchdog.sh /docker/
COPY healthcheck.sh /docker/
COPY http-probe.sh /docker/

COPY templates /docker/templates

RUN chmod +x /docker/entrypoint.sh /docker/watchdog.sh /docker/healthcheck.sh /docker/http-probe.sh

HEALTHCHECK --interval=30s --timeout=15s --start-period=5m --retries=3 \
  CMD /docker/healthcheck.sh

ENTRYPOINT ["/docker/entrypoint.sh"]
