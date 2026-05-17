ARG CNPG_TAG=18.3
ARG VECTORCHORD_TAG=1.1.1
ARG PG_JSONSCHEMA_VERSION=0.3.4
ARG OS=trixie

# ---- Stage 1: copy all extensions from TensorChord reference image ----
FROM tensorchord/vchord-suite:pg${CNPG_TAG%.*}-latest AS ref

# ---- Stage 2: build the CNPG-compatible image ----
ARG CNPG_TAG
ARG VECTORCHORD_TAG
ARG PG_JSONSCHEMA_VERSION
ARG OS=trixie
ARG TARGETARCH

FROM ghcr.io/cloudnative-pg/postgresql:${CNPG_TAG}-standard-${OS}

ARG CNPG_TAG
ARG VECTORCHORD_TAG
ARG PG_JSONSCHEMA_VERSION
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

# Install pg_jsonschema (pre-built DEB from Supabase — only available for PG14-18)
# Using conditional: only downloads for PG18 builds
RUN set -eux; \
    PG_MAJOR="${CNPG_TAG%.*}"; \
    if [ "$PG_MAJOR" = "18" ] && [ -n "${PG_JSONSCHEMA_VERSION:-}" ]; then \
      apt-get update && apt-get install -y --no-install-recommends curl && \
      curl -fSL -o /tmp/pg_jsonschema.deb \
        "https://github.com/supabase/pg_jsonschema/releases/download/v${PG_JSONSCHEMA_VERSION}/pg_jsonschema-v${PG_JSONSCHEMA_VERSION}-pg${PG_MAJOR}-${TARGETARCH}-linux-gnu.deb"; \
      apt-get update && apt-get install -y --no-install-recommends /tmp/pg_jsonschema.deb; \
      rm -f /tmp/pg_jsonschema.deb; \
    fi

# Install json_schema_support extension (pure SQL extension)
# Installs: json_schemas table + validate_payload_against_registry() function
# Only installed for PG18 since it depends on pg_jsonschema
COPY docker/postgresql/18/extension/json_schema_support--0.1.0.sql /tmp/json_schema_support--0.1.0.sql
COPY docker/postgresql/18/extension/json_schema_support.control /tmp/json_schema_support.control
RUN set -eux; \
    PG_MAJOR="${CNPG_TAG%.*}"; \
    if [ "$PG_MAJOR" = "18" ]; then \
      cp /tmp/json_schema_support--0.1.0.sql "/usr/share/postgresql/${PG_MAJOR}/extension/" && \
      cp /tmp/json_schema_support.control "/usr/share/postgresql/${PG_MAJOR}/extension/" && \
      rm /tmp/json_schema_support--0.1.0.sql /tmp/json_schema_support.control; \
    fi

# Cleanup
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

USER postgres
