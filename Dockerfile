FROM ubuntu:26.04

RUN apt update && \
  apt upgrade -y && \
  apt install -y ca-certificates iproute2 iputils-ping gettext-base vim curl openssh-client wireguard ansible

COPY wg0.conf.template /etc/wireguard/wg0.conf.template

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
