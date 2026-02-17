#!/bin/bash
set -euo pipefail

WIREGUARD_CONFIG_TEMPLATE_FILE=/etc/wireguard/wg0.conf.template
WIREGUARD_CONFIG_FILE=/etc/wireguard/wg0.conf
SSH_DIR=/root/.ssh

vault_password=''
security_config=''
ssh_command=''
declare -A security_config_properties

process_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vault-password=*)
        vault_password="${1#*=}"
        shift
        ;;
      --security-config=*)
        security_config="${1#*=}"
        shift
        ;;
      --ssh-command=*)
        ssh_command="${1#*=}"
        shift
        ;;
      *)
        echo "Unknown argument: ${1%%[= ]*}"
        exit 1
        ;;
    esac
  done
  if [[ -z "$vault_password" ]]; then
    echo "Error: --vault-password argument is required"
    exit 1
  fi
  if [[ -z "$security_config" ]]; then
    echo "Error: --security-config argument is required"
    exit 1
  fi
}

load_security_config_properties() {
  local line
  local key
  local value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" != *"="* || "$line" =~ ^[[:blank:]]*#.*$ ]] && continue
    key=$(echo "${line%%=*}" | xargs)
    value=$(echo "${line#*=}" | xargs)
    [[ -z "$key" || -z "$value" ]] && continue
    security_config_properties["$key"]="$value"
  done <<< $(ansible-vault view --vault-password-file=<(echo "$vault_password") <(echo "$security_config" | tr '|' '\n'))
}

create_wireguard_config() {
  WG_PRIVATE_KEY="${security_config_properties[WIREGUARD_PRIVATE_KEY]}" \
  WG_PUBLIC_KEY="${security_config_properties[WIREGUARD_PUBLIC_KEY]}" \
  WG_PRESHARED_KEY="${security_config_properties[WIREGUARD_PRESHARED_KEY]}" \
  WG_ENDPOINT="${security_config_properties[WIREGUARD_ENDPOINT]}" \
  envsubst '${WG_PRIVATE_KEY} ${WG_PUBLIC_KEY} ${WG_PRESHARED_KEY} ${WG_ENDPOINT}' < "$WIREGUARD_CONFIG_TEMPLATE_FILE" > "$WIREGUARD_CONFIG_FILE"
}

create_ssh_config() {
  mkdir -m 600 "$SSH_DIR"
  echo "${security_config_properties[SSH_SERVER_PUBLIC_HOST_KEY]}" > $SSH_DIR/known_hosts
  echo "${security_config_properties[SSH_USER_PRIVATE_KEY]}" | tr '|' '\n' > "$SSH_DIR/id_ed25519"
  chmod 400 "$SSH_DIR/id_ed25519"
}

wireguard_up() {
  echo '**** Starting WireGuard VPN connection ****'
  wg-quick up wg0
}

execute_ssh_command() {
  echo '**** Executing SSH command ****'
  ssh -p "${security_config_properties[SSH_SERVER_PORT]}" "${security_config_properties[SSH_USERNAME]}"@"${security_config_properties[SSH_SERVER_ADDRESS]}" "$ssh_command"
}

main() {
  process_args "$@"
  load_security_config_properties
  create_wireguard_config
  create_ssh_config
  wireguard_up
  execute_ssh_command
}

main "$@"
