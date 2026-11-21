# Least-privilege application identity used by the workloads on the app server.
# NOTE: IAM permission sets are project-scoped; they cannot target a single bucket.

data "scaleway_account_project" "current" {}

resource "scaleway_iam_application" "app" {
  name        = "${var.name_prefix}-app"
  description = "Workload identity for proposal 7 (object storage, registry pull, Generative APIs)"
}

resource "scaleway_iam_policy" "documents_rw" {
  name           = "${var.name_prefix}-documents-rw"
  description    = "Read/write objects in Object Storage"
  application_id = scaleway_iam_application.app.id

  rule {
    project_ids = [data.scaleway_account_project.current.id]
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
    project_ids          = [data.scaleway_account_project.current.id]
    permission_set_names = ["ContainerRegistryReadOnly"]
  }
}

resource "scaleway_iam_policy" "generative_apis" {
  name           = "${var.name_prefix}-generative-apis"
  description    = "Call Scaleway Generative APIs"
  application_id = scaleway_iam_application.app.id

  rule {
    project_ids          = [data.scaleway_account_project.current.id]
    permission_set_names = ["GenerativeApisFullAccess"]
  }
}

resource "scaleway_iam_api_key" "app" {
  application_id     = scaleway_iam_application.app.id
  description        = "${var.name_prefix} application key"
  default_project_id = data.scaleway_account_project.current.id

  depends_on = [
    scaleway_iam_policy.documents_rw,
    scaleway_iam_policy.registry_pull,
    scaleway_iam_policy.generative_apis,
  ]
}
