# Managed PostgreSQL, reachable only through the Private Network
# (no load_balancer endpoint, no ACL needed). No Redis in this design.

resource "random_password" "db_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "db_app" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "scaleway_rdb_instance" "main" {
  name      = "${var.name_prefix}-pg"
  node_type = var.db_node_type
  engine    = var.db_engine
  tags      = var.tags

  is_ha_cluster      = var.db_is_ha
  volume_type        = var.db_volume_type
  volume_size_in_gb  = var.db_volume_size_gb
  encryption_at_rest = var.db_encryption_at_rest

  disable_backup            = false
  backup_schedule_frequency = var.db_backup_frequency_hours
  backup_schedule_retention = var.db_backup_retention_days

  user_name = var.db_admin_user
  password  = random_password.db_admin.result

  private_network {
    pn_id       = scaleway_vpc_private_network.main.id
    enable_ipam = true
  }

  # Protection against destruction. Terraform refuses any plan that would
  # delete or replace this instance (terraform destroy, or a change to an
  # attribute that forces replacement such as engine or encryption_at_rest).
  # prevent_destroy must be a literal: to delete the database on purpose,
  # set it to false, run terraform apply, then destroy. See README.
  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_rdb_database" "app" {
  instance_id = scaleway_rdb_instance.main.id
  name        = var.db_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_rdb_user" "app" {
  instance_id = scaleway_rdb_instance.main.id
  name        = var.db_app_user
  password    = random_password.db_app.result
  is_admin    = false
}

resource "scaleway_rdb_privilege" "app" {
  instance_id   = scaleway_rdb_instance.main.id
  database_name = scaleway_rdb_database.app.name
  user_name     = scaleway_rdb_user.app.name
  permission    = "all"
}
