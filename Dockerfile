# NOTE: Debian Testing (Forky) is currently required because the version of libgd-barcode-perl in Trixie is too old for Koha.
FROM debian:testing
MAINTAINER Phil Pemberton "philpem@philpem.me.uk"

# https://koha-community.org/
ARG KOHA_VERSION=stable
ARG PKG_URL=https://debian.koha-community.org/koha

# Install Debian baseline packages
RUN apt-get update && apt-get install -y \
  wget \
  gnupg

# Make sure we have libgd-barcode-perl 2.01 or later
# If there's a problem here, run Debian Testing instead of Stable.
RUN apt-get -y satisfy "libgd-barcode-perl (>= 2.01)"

# Set up the Koha repository and install it
RUN \
  if [ "${PKG_URL}" = "https://debian.koha-community.org/koha" ]; then \
    wget -q -O /etc/apt/trusted.gpg.d/koha.asc https://debian.koha-community.org/koha/gpg.asc ;  \
  fi ; \
  echo "deb ${PKG_URL} ${KOHA_VERSION} main" | tee /etc/apt/sources.list.d/koha.list ; \
  apt-get update && apt-get install -y \
    koha-common

# Enable some Apache modules and disable the default site
RUN a2enmod rewrite \
           headers \
           proxy_http \
           cgi \
    && a2dissite 000-default

RUN mkdir /docker

COPY entrypoint.sh /docker/

COPY templates /docker/templates

RUN chmod +x /docker/entrypoint.sh

ENTRYPOINT ["/docker/entrypoint.sh"]
