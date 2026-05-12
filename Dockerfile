ARG CNPG_TAG=18.3
ARG VECTORCHORD_TAG=1.1.1
ARG OS=trixie

# ---- Stage 1: copy all extensions from TensorChord reference image ----
FROM tensorchord/vchord-suite:pg${CNPG_TAG%.*}-latest AS ref

# ---- Stage 2: build the CNPG-compatible image ----
ARG CNPG_TAG
ARG VECTORCHORD_TAG
ARG OS=trixie
ARG TARGETARCH

FROM ghcr.io/cloudnative-pg/postgresql:${CNPG_TAG}-standard-${OS}

ARG CNPG_TAG
ARG VECTORCHORD_TAG
ARG TARGETARCH

# drop to root to install packages
USER root
RUN mkdir -p /var/lib/apt/lists/partial

# Install vchord from TensorChord release DEB (gets vchord.so + C dependencies)
ADD https://github.com/tensorchord/VectorChord/releases/download/$VECTORCHORD_TAG/postgresql-${CNPG_TAG%.*}-vchord_${VECTORCHORD_TAG#"v"}-1_$TARGETARCH.deb /tmp/vchord.deb
RUN apt-get update && apt-get install -y /tmp/vchord.deb && rm -f /tmp/vchord.deb

# Copy the remaining extension files from the reference image
COPY --from=ref /usr/lib/postgresql/${CNPG_TAG%.*}/lib/vchord_bm25.so /usr/lib/postgresql/${CNPG_TAG%.*}/lib/vchord_bm25.so
COPY --from=ref /usr/lib/postgresql/${CNPG_TAG%.*}/lib/pg_tokenizer.so /usr/lib/postgresql/${CNPG_TAG%.*}/lib/pg_tokenizer.so
COPY --from=ref /usr/lib/postgresql/${CNPG_TAG%.*}/lib/vector.so /usr/lib/postgresql/${CNPG_TAG%.*}/lib/vector.so
COPY --from=ref /usr/lib/postgresql/${CNPG_TAG%.*}/lib/bitcode /usr/lib/postgresql/${CNPG_TAG%.*}/lib/bitcode
COPY --from=ref /usr/share/postgresql/${CNPG_TAG%.*}/extension/vchord_bm25* /usr/share/postgresql/${CNPG_TAG%.*}/extension/
COPY --from=ref /usr/share/postgresql/${CNPG_TAG%.*}/extension/pg_tokenizer* /usr/share/postgresql/${CNPG_TAG%.*}/extension/
COPY --from=ref /usr/share/postgresql/${CNPG_TAG%.*}/extension/vector* /usr/share/postgresql/${CNPG_TAG%.*}/extension/

# Cleanup
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

USER postgres
