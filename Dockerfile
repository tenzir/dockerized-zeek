# -- development ---------------------------------------------------------------

# This build stage provides Zeek and related management utilities.
FROM --platform=linux/amd64 debian:bookworm-slim AS development

LABEL maintainer="engineering@tenzir.com"
LABEL org.opencontainers.image.authors="engineering@tenzir.com"
LABEL org.opencontainers.image.url="https://github.com/tenzir/dockerized-zeek/"
LABEL org.opencontainers.image.source="https://github.com/tenzir/dockerized-zeek"
LABEL org.opencontainers.image.title="tenzir/dockerized-zeek"
LABEL org.opencontainers.image.description="Dockerized Zeek"

# The Zeek version according to the official release tags.
# Alternatives: zeek, zeek-6.0
ARG ZEEK_PACKAGE=zeek

# Packages to install via zkg (white-space separated list).
ARG ZEEK_PACKAGES="corelight/zeek-spicy-facefish \
                   corelight/zeek-spicy-ipsec \
                   corelight/zeek-spicy-openvpn \
                   corelight/zeek-spicy-ospf \
                   corelight/zeek-spicy-stun \
                   corelight/zeek-spicy-wireguard \
                   zeek/spicy-dhcp \
                   zeek/spicy-dns \
                   zeek/spicy-http \
                   zeek/spicy-pe \
                   zeek/spicy-png \
                   zeek/spicy-tftp \
                   zeek/spicy-zip \
                   foxio/ja4 \
                   salesforce/ja3"

# Package dependencies to install via apt (white-space separated list).
ARG ZEEK_PACKAGE_DEPENDENCIES="linux-headers-amd64"

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
    echo setting up Zeek apt repo && \
    echo 'deb [signed-by=/etc/apt/keyrings/zeek.asc] http://download.opensuse.org/repositories/security:/zeek/Debian_12/ /' | tee /etc/apt/sources.list.d/security:zeek.list && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL -o /etc/apt/keyrings/zeek.asc https://download.opensuse.org/repositories/security:zeek/Debian_12/Release.key && \
    apt-get update && \
    echo installing Zeek && \
    apt-get -y --no-install-recommends install \
      $ZEEK_PACKAGE && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN echo "setting up Zeek packages" && \
    zkg autoconfig --force && \
    sed -i '/@load packages/s/^#*\s*//g' \
      "$(zeek-config --site_dir)"/local.zeek && \
    echo installing user-specified packages && \
    apt-get update && \
    for dep in $ZEEK_PACKAGE_DEPENDENCIES; do \
      apt-get -y --no-install-recommends install "$dep"; \
    done && \
    git config --global --add safe.directory /opt/zeek/var/lib/zkg/clones/source/zeek && \
    for pkg in $ZEEK_PACKAGES; do \
      zkg -vv install --force --skiptests "$pkg" || cat /opt/zeek/var/lib/zkg/logs/*-build.log; \
    done && \
    rm -rf /var/lib/apt/lists/*

# Install ipsumdump for merging traces.
RUN echo installing ipsumdump for trace processing && \
     mkdir ipsumdump-src && cd ipsumdump-src && \
     curl -sSL \
       "https://github.com/chemag/ipsumdump/archive/a3667e543ee1a3b7c6453c3523990d4989a230bb.tar.gz" | \
     tar -xz --strip-components=1 && \
     mkdir build && cd build && \
     ../configure --enable-all-elements --prefix /opt/zeek && \
     make install && \
     cd ../.. && \
     rm -rf ipsumdump-src

# -- production ----------------------------------------------------------------

# This build stage provides a "user interface" for Zeek to enable live and
# trace-based packet analysis.
FROM --platform=linux/amd64 debian:bookworm-slim AS production

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
