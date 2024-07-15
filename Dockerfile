FROM dbgate/dbgate:5.3.1 AS dbgate

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
    ca-certificates wget mariadb-server mariadb-client nodejs unixodbc pwgen lighttpd && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm /etc/mysql/mariadb.conf.d/50-server.cnf

RUN \
  # install yq
  wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${PLATFORM} && \
  echo "${YQ_SHA} /tmp/yq" | sha256sum -c || exit 1 && \ 
  mv /tmp/yq /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# remove so we can manually handle db initalization
RUN rm -rf /var/lib/mysql/

COPY --from=dbgate /home/dbgate-docker /home/dbgate-docker

ADD ./docker_entrypoint.sh /usr/local/bin/docker_entrypoint.sh

# Add our demo app

COPY ./app /var/www/html
