# ---------------------------------------------------------------------------
# Terraform and provider versions
#
# Terraform does not allow variables in version constraints, so the versions
# are set here, as literals. To change one:
#   1. edit the `version` below (keep it exact, avoid open ranges)
#   2. run: ./tf.sh <env> init -upgrade
#   3. commit the updated .terraform.lock.hcl
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "2.93.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

# ---------------------------------------------------------------------------
# Scaleway provider
#
# Credentials are NOT set here. Export them as environment variables:
#   SCW_ACCESS_KEY, SCW_SECRET_KEY, SCW_DEFAULT_ORGANIZATION_ID
#
# Do NOT export SCW_DEFAULT_PROJECT_ID: when both the environment variable and
# var.project_id are set, the environment variable wins and silently overrides
# the project of envs/<env>.tfvars (a dev run could land in the prod project).
# tf.sh unsets it when the tfvars file defines project_id.
#
# region, zone and project_id come from variables (envs/<env>.tfvars) and are
# inherited by every resource, so one deployment targets one region and project.
# ---------------------------------------------------------------------------
provider "scaleway" {
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}

# The random provider needs no configuration.
provider "random" {}
