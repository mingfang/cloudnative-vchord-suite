ARG CNPG_TAG
ARG OS=bookworm

FROM ghcr.io/cloudnative-pg/postgresql:${CNPG_TAG%.*}-${OS}

ARG CNPG_TAG
ARG VECTORCHORD_TAG
ARG TARGETARCH

# drop to root to install packages
USER root
RUN mkdir -p /var/lib/apt/lists/partial

ADD https://github.com/tensorchord/VectorChord/releases/download/$VECTORCHORD_TAG/postgresql-${CNPG_TAG%.*}-vchord_${VECTORCHORD_TAG#"v"}-1_$TARGETARCH.deb /tmp/vchord.deb
RUN apt-get update && apt-get install -y /tmp/vchord.deb && rm -f /tmp/vchord.deb && apt-get clean && rm -rf /var/lib/apt/lists/*

USER postgres
