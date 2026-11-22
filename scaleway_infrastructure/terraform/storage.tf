locals {
  documents_bucket_name   = coalesce(var.documents_bucket_name, "${var.name_prefix}-documents-${var.bucket_suffix}")
  backups_bucket_name     = coalesce(var.backups_bucket_name, "${var.name_prefix}-backups-${var.bucket_suffix}")
  registry_namespace_name = coalesce(var.registry_namespace_name, "${var.name_prefix}-registry-${var.bucket_suffix}")
}

resource "scaleway_registry_namespace" "main" {
  name        = local.registry_namespace_name
  description = "Private container registry for proposal 7"
  is_public   = false
}

resource "scaleway_object_bucket" "documents" {
  name          = local.documents_bucket_name
  force_destroy = var.buckets_force_destroy
  tags          = { for i, t in var.tags : "tag${i}" => t }
}

resource "scaleway_object_bucket" "backups" {
  name          = local.backups_bucket_name
  force_destroy = var.buckets_force_destroy
  tags          = { for i, t in var.tags : "tag${i}" => t }

  versioning {
    enabled = true
  }
}

resource "scaleway_object_bucket_acl" "documents" {
  bucket = scaleway_object_bucket.documents.id
  acl    = "private"
}

resource "scaleway_object_bucket_acl" "backups" {
  bucket = scaleway_object_bucket.backups.id
  acl    = "private"
}
