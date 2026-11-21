# Credentials are NOT set here. Export them as environment variables:
#   SCW_ACCESS_KEY, SCW_SECRET_KEY, SCW_DEFAULT_PROJECT_ID, SCW_DEFAULT_ORGANIZATION_ID
provider "scaleway" {
  region     = var.region
  zone       = var.zone
  project_id = var.project_id
}
