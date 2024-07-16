# DbGate container
FROM dbgate/dbgate:5.3.1 AS dbgate

# Start from bookworm-slim
FROM debian:bookworm-slim

# these are specified in Makefile
ARG PLATFORM
ARG YQ_VERSION
ARG YQ_SHA

# Install necessary packages
RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
    # install wget and certificates
    ca-certificates wget \
    # install mariadb server and client
    mariadb-server mariadb-client pwgen \
    # nodejs for DbGate
    nodejs \
    # lighttpd for our 'app'
    lighttpd && \
  # clean up to keep container small
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

RUN \
  # install yq
  wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${PLATFORM} && \
  echo "${YQ_SHA} /tmp/yq" | sha256sum -c || exit 1 && \ 
  mv /tmp/yq /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# remove default mariadb config and data files,
# so we can manually handle db initalization
RUN \
  rm -r /etc/mysql/mariadb.conf.d/50-server.cnf && \
  rm -r /var/lib/mysql/

# add DbGate
COPY --from=dbgate /home/dbgate-docker /home/dbgate-docker

# add entrypoint script
COPY ./docker_entrypoint.sh /usr/local/bin/docker_entrypoint.sh

# Add demo app
COPY ./app /var/www/html
