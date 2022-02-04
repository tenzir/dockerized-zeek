# -- development ---------------------------------------------------------------

# This build stage provides Zeek and related management utilities.
FROM --platform=linux/amd64 debian:bullseye-slim AS development

LABEL maintainer="engineering@tenzir.com"
LABEL org.opencontainers.image.authors="engineering@tenzir.com"
LABEL org.opencontainers.image.url="https://github.com/tenzir/dockerized-zeek/"
LABEL org.opencontainers.image.source="https://github.com/tenzir/dockerized-zeek"
LABEL org.opencontainers.image.title="tenzir/dockerized-zeek"
LABEL org.opencontainers.image.description="Dockerized Zeek"

# The Zeek version according to the official release tags.
ARG ZEEK_VERSION=4.2.0-0

# The mirror where to download DEBs from.
ARG ZEEK_MIRROR="https://download.zeek.org/binary-packages/Debian_11/amd64"

# Boolean flag to choose between regular and LTS version.
# A non-empty value enables the LTS build.
ARG ZEEK_LTS=

# The Spicy deb is not distributed along at Zeek mirrors, which is why we need
# to track it manually.
ARG SPICY_DEB="https://github.com/zeek/spicy/releases/download/v1.3.0/spicy_linux_debian11.deb"

# Packages to install via zkg (white-space separated list).
ARG ZEEK_PACKAGES="zeek-af_packet-plugin:master \
                   corelight/zeek-spicy-facefish \
                   corelight/zeek-spicy-ipsec \
                   corelight/zeek-spicy-openvpn \
                   corelight/zeek-spicy-ospf \
                   corelight/zeek-spicy-stun \
                   corelight/zeek-spicy-wireguard \
                   zeek/spicy-dhcp \
                   zeek/spicy-dns \
                   zeek/spicy-http \
                   zeek/spicy-ldap \
                   zeek/spicy-pe \
                   zeek/spicy-png \
                   zeek/spicy-tftp \
                   zeek/spicy-zip \
                   salesforce/ja3"

# Package dependencies to install via apt (white-space separated list).
ARG ZEEK_PACKAGE_DEPENDENCIES="linux-headers-amd64"

# Limit parallelism for the spicy build to avoid running out of memory.
ARG SPICY_ZKG_PROCESSES=1

ENV PATH="/opt/zeek/bin:/opt/spicy/bin:${PATH}"

RUN echo installing build system packages && \
    apt-get update && \
    apt-get -y --no-install-recommends install \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      g++ \
      iproute2 \
      libcap2-bin \
      pkg-config && \
      apt-get -y --no-install-recommends install \
        python3-git \
        python3-pip \
        python3-semantic-version \
        python3-setuptools \
        python3-wheel && \
    echo installing Zeek-specific dependencies && \
    apt-get -y --no-install-recommends install \
      libmaxminddb-dev \
      libmaxminddb0 \
      libpcap-dev \
      libpcap0.8 \
      libssl-dev \
      zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

COPY zkg-install /usr/local/bin

RUN echo "fetching Zeek $ZEEK_VERSION" && \
    export lts=${ZEEK_LTS:+"-lts"} && \
    curl -sSL --remote-name-all \
      "${ZEEK_MIRROR}/libbroker${lts}-dev_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeek${lts}-btest_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeek${lts}-core-dev_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeek${lts}-core_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeek${lts}-libcaf-dev_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeek${lts}_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeek${lts}-zkg_${ZEEK_VERSION}_amd64.deb" \
      "${ZEEK_MIRROR}/zeekctl${lts}_${ZEEK_VERSION}_amd64.deb" && \
    case $ZEEK_VERSION in 4.[1-9].*) \
      curl -sSL --remote-name-all \
        "${ZEEK_MIRROR}/zeek${lts}-btest-data_${ZEEK_VERSION}_amd64.deb" \
      ;; \
    esac && \
    curl -sSL --remote-name-all "${SPICY_DEB}" && \
    echo "installing Zeek $ZEEK_VERSION, LTS=$ZEEK_LTS" && \
    dpkg -i *.deb && \
    rm -rf *.deb

RUN echo "setting up Zeek packages" && \
    zkg autoconfig --force && \
    sed -i '/@load packages/s/^#*\s*//g' \
      "$(zeek-config --site_dir)"/local.zeek && \
    echo installing Spicy plugin && \
    export SPICY_ZKG_PROCESSES=$SPICY_ZKG_PROCESSES && \
    zkg-install zeek/spicy-plugin && \
    echo installing user-specified packages && \
    apt-get update && \
    for dep in $ZEEK_PACKAGE_DEPENDENCIES; do \
      apt-get -y --no-install-recommends install "$dep"; \
    done && \
    for pkg in $ZEEK_PACKAGES; do \
      zkg-install "$pkg"; \
    done && \
    rm -rf /var/lib/apt/lists/*

# Install ipsumdump for merging traces.
RUN echo installing ipsumdump for trace processing && \
     curl -sSL --remote-name-all \
       "https://github.com/kohler/ipsumdump/archive/refs/tags/v1.86.tar.gz" && \
     tar xzf v1.86.tar.gz && \
     mkdir ipsumdump-1.86/build && \
     cd ipsumdump-1.86/build && \
     ../configure --enable-all-elements --prefix /opt/zeek && \
     make install && \
     cd ../.. && \
     rm -rf ipsumdump-1.86.tar.gz ipsdump-1.86

# -- production ----------------------------------------------------------------

# This build stage provides a "user interface" for Zeek to enable live and
# trace-based packet analysis.
FROM --platform=linux/amd64 debian:bullseye-slim AS production

ENV PATH="/opt/zeek/bin:/opt/spicy/bin:${PATH}"

# Directory added to $ZEEKPATH from where users can load custom scripts.
ENV ZEEK_SCRIPT_DIR="/zeek"

# Arguments to pass to the auto-generated Zeek command line.
ENV ZEEK_ARGS=""

# Zeek scripts to load by default. These should be valid within the base
# distribution or within $ZEEK_SCRIPT_DIR.
ENV ZEEK_SCRIPTS="local docker-entrypoint"

# Flag to control passing -C to Zeek in order to toggle IP checksum validation.
ENV ZEEK_DISABLE_CHECKSUMS="true"

# The interface name for when performing live packet analysis.
ENV ZEEK_INTERFACE="eth0"

RUN apt-get update && \
    apt-get -y --no-install-recommends install \
      iproute2 \
      libcap2-bin \
      libmaxminddb0 \
      libpcap0.8 \
      python3-git \
      python3-minimal \
      python3-pip \
      python3-semantic-version && \
    rm -rf /var/lib/apt/lists/*

# The user owning all files.
RUN useradd --system --user-group zeek

# Copy Zeek tree from development stage.
COPY --from=development --chown=zeek:zeek /opt/ /opt/
COPY --chown=zeek:zeek scripts/ /zeek

# Adjust interface permissions to capture as non-root user.
RUN setcap CAP_NET_RAW+eip /opt/zeek/bin/zeek

# Prepare entry point.
COPY docker_entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/docker_entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker_entrypoint.sh"]
