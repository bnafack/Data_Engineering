#!/usr/bin/env bash
# Run Terraform for one environment, with its own variables and its own state.
# No Terraform workspaces: each environment has a separate state file or key.
#
#   ./tf.sh <dev|prod> <command> [terraform args...]
#
# Examples:
#   ./tf.sh dev init
#   ./tf.sh dev plan -out tfplan-dev
#   ./tf.sh prod apply tfplan-prod
#
# Informational lines go to stderr, so `./tf.sh <env> output -json` is valid JSON on stdout.
#
# The state backend is chosen by backend.tf (copy one of the examples):
#   - backend.s3.tf.example    -> remote S3 state, settings in envs/<env>.backend.hcl
#   - backend.local.tf.example -> local state in states/<env>/terraform.tfstate
set -euo pipefail

cd "$(dirname "$0")"

usage() {
  echo "Usage: $0 <dev|prod> <init|validate|plan|apply|destroy|output|console|...> [args]" >&2
  exit 1
}

[[ $# -ge 2 ]] || usage
env="$1"
cmd="$2"
shift 2

case "$env" in
  dev | prod) ;;
  *) echo "Unknown environment '$env' (expected dev or prod)." >&2; usage ;;
esac

varfile="envs/${env}.tfvars"
backendfile="envs/${env}.backend.hcl"

if [[ ! -f "$varfile" ]]; then
  echo "Missing $varfile. Create it: cp envs/${env}.tfvars.example $varfile" >&2
  exit 1
fi

# If this environment sets project_id, make sure an exported
# SCW_DEFAULT_PROJECT_ID cannot override it (the environment variable wins
# over the provider block, which would send a dev run to another project).
if grep -Eq '^[[:space:]]*project_id[[:space:]]*=[[:space:]]*"' "$varfile"; then
  if [[ -n "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
    echo ">> note: ignoring exported SCW_DEFAULT_PROJECT_ID; using project_id from $varfile" >&2
  fi
  unset SCW_DEFAULT_PROJECT_ID
fi

if [[ ! -f backend.tf ]]; then
  echo "Missing backend.tf. Choose where the state is stored:" >&2
  echo "  remote: cp backend.s3.tf.example backend.tf" >&2
  echo "  local : cp backend.local.tf.example backend.tf" >&2
  exit 1
fi

# Select this environment's state on every run, so a command can never run
# against the other environment's state.
if grep -Eq '^[[:space:]]*backend[[:space:]]+"local"' backend.tf; then
  statefile="states/${env}/terraform.tfstate"
  mkdir -p "states/${env}"
  backend_arg="-backend-config=path=${statefile}"
  state_desc="local ($statefile)"
else
  if [[ ! -f "$backendfile" ]]; then
    echo "Missing $backendfile. Create it: cp envs/${env}.backend.hcl.example $backendfile" >&2
    exit 1
  fi
  backend_arg="-backend-config=${backendfile}"
  state_desc="remote ($backendfile)"
fi

terraform init -input=false -reconfigure "$backend_arg" > /dev/null

echo ">> environment: $env | vars: $varfile | state: $state_desc" >&2

case "$cmd" in
  init)
    echo "Initialised for $env." >&2
    ;;
  plan | apply | destroy | console | import | refresh)
    # apply with a saved plan file does not accept -var-file
    if [[ "$cmd" == "apply" && $# -ge 1 && "${1:0:1}" != "-" ]]; then
      terraform apply "$@"
    else
      terraform "$cmd" -var-file="$varfile" "$@"
    fi
    ;;
  *)
    terraform "$cmd" "$@"
    ;;
esac
