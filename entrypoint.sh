#!/bin/bash
set -euo pipefail

TEMPLATES_DIR=/root/templates
ANSIBLE_PASSWORD_FILE=/root/.pwd
WIREGUARD_CONFIG_FILE=/etc/wireguard/wg0.conf
SSH_DIR=/root/.ssh
SSH_PRIVATE_KEY_FILE="$SSH_DIR/id_ed25519"
SSH_KNOWN_HOSTS_FILE="$SSH_DIR/known_hosts"
SSH_CONFIG_FILE="$SSH_DIR/config"

vault_password=''
security_config=''
ssh_command=''
ansible_tags=''
ansible_playbook=''
ansible_dry_run=1
ansible_verbose=0
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
      --ansible-tags=*)
        ansible_tags="${1#*=}"
        shift
        ;;
      --ansible-playbook=*)
        ansible_playbook="${1#*=}"
        shift
        ;;
      --ansible-dry-run=*)
        [[ ${1#*=} == 'false' ]] && ansible_dry_run=0
        shift
        ;;
      --ansible-verbose=*)
        [[ ${1#*=} == 'true' ]] && ansible_verbose=1
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

configure_ansible() {
  echo "$vault_password" > "$ANSIBLE_PASSWORD_FILE"
  chmod 400 "$ANSIBLE_PASSWORD_FILE"
  export ANSIBLE_VAULT_PASSWORD_FILE="$ANSIBLE_PASSWORD_FILE"
  export ANSIBLE_FORCE_COLOR=true
}

load_security_config_properties() {
  local config
  local line
  local key
  local value
  config=$(ansible-vault view <(echo "$security_config" | tr '|' '\n'))
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" != *"="* || "$line" =~ ^[[:blank:]]*#.*$ ]] && continue
    key=$(echo "${line%%=*}" | xargs)
    value=$(echo "${line#*=}" | xargs)
    [[ -z "$key" || -z "$value" ]] && continue
    security_config_properties["$key"]="$value"
  done <<< "$config"
}

create_wireguard_config() {
  WG_PRIVATE_KEY="${security_config_properties[WIREGUARD_PRIVATE_KEY]}" \
  WG_PUBLIC_KEY="${security_config_properties[WIREGUARD_PUBLIC_KEY]}" \
  WG_PRESHARED_KEY="${security_config_properties[WIREGUARD_PRESHARED_KEY]}" \
  WG_ENDPOINT="${security_config_properties[WIREGUARD_ENDPOINT]}" \
  envsubst '${WG_PRIVATE_KEY} ${WG_PUBLIC_KEY} ${WG_PRESHARED_KEY} ${WG_ENDPOINT}' < "$TEMPLATES_DIR/wg0.conf.template" > "$WIREGUARD_CONFIG_FILE"
  chmod 400 "$WIREGUARD_CONFIG_FILE"
}

create_ssh_config() {
  mkdir -m 600 "$SSH_DIR"
  echo "${security_config_properties[SSH_SERVER_PUBLIC_HOST_KEY]}" > $SSH_KNOWN_HOSTS_FILE
  echo "${security_config_properties[SSH_USER_PRIVATE_KEY]}" | tr '|' '\n' > "$SSH_PRIVATE_KEY_FILE"
  chmod 400 "$SSH_PRIVATE_KEY_FILE"
  SSH_SERVER_ADDRESS="${security_config_properties[SSH_SERVER_ADDRESS]}" \
  SSH_SERVER_PORT="${security_config_properties[SSH_SERVER_PORT]}" \
  SSH_USERNAME="${security_config_properties[SSH_USERNAME]}" \
  envsubst '${SSH_SERVER_ADDRESS} ${SSH_SERVER_PORT} ${SSH_USERNAME}' < "$TEMPLATES_DIR/ssh-config.template" > "$SSH_CONFIG_FILE"
  chmod 400 "$SSH_CONFIG_FILE"
}

wireguard_up() {
  echo '***** Starting WireGuard VPN connection *****'
  wg-quick up wg0
}

execute_ssh_command() {
  echo '***** Executing SSH command *****'
  echo "$ssh_command"
  ssh target "$ssh_command"
}

execute_ansible_playbook() {
  echo '***** Executing Ansible playbook *****'
  local cmd=(ansible-playbook --extra-vars 'host=target')
  [[ -n "$ansible_tags" ]] && cmd+=(--tags "$ansible_tags")
  cmd+=(--diff)
  (( $ansible_dry_run )) && cmd+=(--check)
  (( $ansible_verbose )) && cmd+=(-vvv)
  cmd+=("$ansible_playbook")
  echo "${cmd[@]}"
  "${cmd[@]}"
}

main() {
  process_args "$@"
  configure_ansible
  load_security_config_properties
  create_wireguard_config
  create_ssh_config
  wireguard_up
  if [[ -n "$ssh_command" ]]; then
    execute_ssh_command
  fi
  if [[ -n "$ansible_playbook" ]]; then
    execute_ansible_playbook
  fi
}

cleanup() {
  exit_code=$?
  if [[ -f "$ANSIBLE_PASSWORD_FILE" ]]; then
    chmod 200 "$ANSIBLE_PASSWORD_FILE"
    shred -n 10 --remove $ANSIBLE_PASSWORD_FILE
  fi
  if [[ -f "$WIREGUARD_CONFIG_FILE" ]]; then
    chmod 200 "$WIREGUARD_CONFIG_FILE"
    shred -n 10 --remove $WIREGUARD_CONFIG_FILE
  fi
  if [[ -f "$SSH_PRIVATE_KEY_FILE" ]]; then
    chmod 200 "$SSH_PRIVATE_KEY_FILE"
    shred -n 10 --remove $SSH_PRIVATE_KEY_FILE
  fi
  exit "$exit_code"
}

trap cleanup EXIT INT TERM
main "$@"
