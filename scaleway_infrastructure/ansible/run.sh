#!/usr/bin/env bash
# Run a playbook for ONE environment, with its own inventory, variables and vault.
#
#   ./run.sh <dev|prod> <playbook> [ansible-playbook args...]
#
# Examples:
#   ./run.sh dev base --check --diff
#   ./run.sh dev site
#   ./run.sh prod site --tags k3s --limit prod-app
#
# <playbook> is a name from playbooks/ (site, base, network, k3s, argocd, cartography, docker),
# with or without .yml.
# Vault password: .vault_pass.<env>, else .vault_pass, else a prompt (only if vault.yml is encrypted).
set -euo pipefail
cd "$(dirname "$0")"
usage() {
  echo "Usage: $0 <dev|prod> <playbook> [ansible-playbook args]" >&2
  exit 1
}
[[ $# -ge 2 ]] || usage
env="$1"
playbook="$2"
shift 2
case "$env" in
  dev | prod) ;;
  *) echo "Unknown environment '$env' (expected dev or prod)." >&2; usage ;;
esac
playbook="${playbook#playbooks/}"
playbook="${playbook%.yml}"
playbook_file="playbooks/${playbook}.yml"
inventory="inventories/${env}/hosts.yml"
vault_file="inventories/${env}/group_vars/all/vault.yml"
if [[ ! -f "$playbook_file" ]]; then
  echo "Unknown playbook '$playbook'. Available:" >&2
  (cd playbooks && ls ./*.yml | sed 's|^\./||; s|\.yml$||' | grep -v '^guard$' | sed 's/^/  /') >&2
  exit 1
fi
if [[ ! -f "$inventory" ]]; then
  echo "Missing $inventory. Generate it: ./gen-inventory.sh ${env} --mode public" >&2
  exit 1
fi
if [[ -f "$vault_file" ]] && ! head -c 14 "$vault_file" | grep -q '^\$ANSIBLE_VAULT' \
  && ! grep -q 'CHANGE_ME' "$vault_file"; then
  echo "Refusing to run: $vault_file holds secrets in clear text. Encrypt it: ansible-vault encrypt $vault_file" >&2
  exit 1
fi
args=(-i "$inventory" -e "env_name=${env}")
if [[ -f "$vault_file" ]] && head -c 14 "$vault_file" | grep -q '^\$ANSIBLE_VAULT'; then
  if [[ -f ".vault_pass.${env}" ]]; then
    args+=(--vault-password-file ".vault_pass.${env}")
  elif [[ -f .vault_pass ]]; then
    args+=(--vault-password-file .vault_pass)
  else
    args+=(--ask-vault-pass)
  fi
fi
echo ">> environment: ${env} | inventory: ${inventory} | playbook: ${playbook_file}" >&2
exec ansible-playbook "${args[@]}" "$@" "$playbook_file"
