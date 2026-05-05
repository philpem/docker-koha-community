# NOTE: Debian Testing (Forky) is currently required because the
# version of libgd-barcode-perl in Trixie is too old for Koha.
FROM debian:testing
LABEL maintainer="philpem@philpem.me.uk"

# Avoid debconf "unable to initialize frontend: Readline" warnings during build.
# ARG instead of ENV so the value doesn't leak into the running container.
ARG DEBIAN_FRONTEND=noninteractive

# https://koha-community.org/
ARG KOHA_VERSION=stable
ARG PKG_URL=https://debian.koha-community.org/koha

# Install Debian baseline packages
# Make sure we have libgd-barcode-perl 2.01 or later
# If there's a problem here, run Debian Testing instead of Stable.
RUN apt-get update && apt-get install -y \
  curl \
  wget \
  gnupg && \
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

COPY templates /docker/templates

RUN chmod +x /docker/entrypoint.sh /docker/watchdog.sh /docker/healthcheck.sh

HEALTHCHECK --interval=30s --timeout=15s --start-period=5m --retries=3 \
  CMD /docker/healthcheck.sh

ENTRYPOINT ["/docker/entrypoint.sh"]
