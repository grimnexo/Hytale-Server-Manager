FROM debian:bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    bash \
    curl \
    wget \
    gpg \
    apt-transport-https \
 && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor \
    | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null \
 && echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" \
    | tee /etc/apt/sources.list.d/adoptium.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    temurin-25-jdk \
    libstdc++6 \
    libgcc-s1 \
    libssl3 \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -s /bin/bash hytale

WORKDIR /opt/hytale

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER hytale

ENTRYPOINT ["entrypoint.sh"]
