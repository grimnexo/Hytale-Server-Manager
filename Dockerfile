FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    bash \
    curl \
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
