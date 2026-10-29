FROM debian:trixie-slim
COPY --from=ghcr.io/jdx/mise:2026.10.8 /usr/local/bin/mise /usr/local/bin/mise

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates coreutils curl findutils gawk git grep jq \
      libpq-dev openssh-client postgresql python3 python3-venv sed unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# initdb は root で実行できないため、検証は一般ユーザーで行う。
ARG LOCAL_UID=1000
ARG LOCAL_GID=1000
RUN groupadd --gid "$LOCAL_GID" validator \
    && useradd --uid "$LOCAL_UID" --gid "$LOCAL_GID" --create-home validator
USER validator
ENV MISE_DATA_DIR=/home/validator/.local/share/mise \
    PATH=/home/validator/.local/share/mise/shims:/opt/toolchain/.venv/bin:/usr/lib/postgresql/17/bin:$PATH
WORKDIR /opt/toolchain
COPY --chown=validator:validator mise.toml ./
COPY --chown=validator:validator automation/toolchain/requirements.txt automation/toolchain/requirements.txt
COPY --chown=validator:validator automation/toolchain/entrypoint.sh ./entrypoint.sh
USER root
RUN chown validator:validator /opt/toolchain
USER validator
RUN mise trust && mise install && mise run setup

WORKDIR /work
ENTRYPOINT ["bash", "/opt/toolchain/entrypoint.sh"]
CMD ["bash", "automation/scripts/ci/validate.sh"]
