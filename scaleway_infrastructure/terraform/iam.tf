# Least-privilege application identity used by the workloads on the app server.
# NOTE: IAM permission sets are project-scoped; they cannot target a single bucket.

# The project ID comes from var.project_id. The data source (which needs the
# "read project" permission) is only used as a fallback when it is null.
data "scaleway_account_project" "current" {
  count = var.project_id == null ? 1 : 0
}

locals {
  project_id = var.project_id != null ? var.project_id : one(data.scaleway_account_project.current[*].id)
}

resource "scaleway_iam_application" "app" {
  name        = "${var.name_prefix}-app"
  description = "Workload identity for proposal 7 (object storage, registry pull, Generative APIs)"
}

resource "scaleway_iam_policy" "documents_rw" {
  name           = "${var.name_prefix}-documents-rw"
  description    = "Read/write objects in Object Storage"
  application_id = scaleway_iam_application.app.id

  rule {
    project_ids = [local.project_id]
    permission_set_names = [
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
      "ObjectStorageBucketsRead",
    ]
  }
}

resource "scaleway_iam_policy" "registry_pull" {
  name           = "${var.name_prefix}-registry-pull"
  description    = "Pull images from Container Registry"
  application_id = scaleway_iam_application.app.id

  rule {
    project_ids          = [local.project_id]
    permission_set_names = ["ContainerRegistryReadOnly"]
  }
}

resource "scaleway_iam_policy" "generative_apis" {
  name           = "${var.name_prefix}-generative-apis"
  description    = "Call Scaleway Generative APIs"
  application_id = scaleway_iam_application.app.id

  rule {
    project_ids          = [local.project_id]
    permission_set_names = ["GenerativeApisFullAccess"]
  }
}

resource "scaleway_iam_api_key" "app" {
  application_id     = scaleway_iam_application.app.id
  description        = "${var.name_prefix} application key"
  default_project_id = local.project_id

  depends_on = [
    scaleway_iam_policy.documents_rw,
    scaleway_iam_policy.registry_pull,
    scaleway_iam_policy.generative_apis,
  ]
}
