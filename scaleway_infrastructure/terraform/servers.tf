# WARNING: Elastic Metal servers are billed as soon as they are created
# (monthly fee, possible commitment). Set create_*_server = false to deploy
# the rest of the stack first.

data "scaleway_baremetal_os" "main" {
  zone    = var.zone
  name    = var.os_name
  version = var.os_version
}

data "scaleway_baremetal_offer" "app" {
  count               = var.create_app_server ? 1 : 0
  zone                = var.zone
  name                = var.app_offer_name
  subscription_period = var.offer_subscription_period
}

data "scaleway_baremetal_option" "app_private_network" {
  count = var.create_app_server ? 1 : 0
  zone  = var.zone
  name  = var.app_private_network_option_name
}

data "scaleway_baremetal_offer" "cartography" {
  count               = var.create_cartography_server ? 1 : 0
  zone                = var.zone
  name                = var.cartography_offer_name
  subscription_period = var.offer_subscription_period
}

data "scaleway_baremetal_option" "cartography_private_network" {
  count = var.create_cartography_server ? 1 : 0
  zone  = var.zone
  name  = var.cartography_private_network_option_name
}

resource "scaleway_baremetal_server" "app" {
  count       = var.create_app_server ? 1 : 0
  name        = "${var.name_prefix}-app"
  hostname    = "${var.name_prefix}-app"
  description = "Application server (k3s, Docker, Argo CD)"
  zone        = var.zone
  offer       = data.scaleway_baremetal_offer.app[0].offer_id
  os          = data.scaleway_baremetal_os.main.os_id
  ssh_key_ids = [for k in scaleway_iam_ssh_key.admin : k.id]
  cloud_init  = var.app_cloud_init
  protected   = var.server_protected
  tags        = var.tags

  options {
    id = data.scaleway_baremetal_option.app_private_network[0].option_id
  }

  private_network {
    id = scaleway_vpc_private_network.main.id
  }
}

resource "scaleway_baremetal_server" "cartography" {
  count       = var.create_cartography_server ? 1 : 0
  name        = "${var.name_prefix}-cartography"
  hostname    = "${var.name_prefix}-cartography"
  description = "Cartography server"
  zone        = var.zone
  offer       = data.scaleway_baremetal_offer.cartography[0].offer_id
  os          = data.scaleway_baremetal_os.main.os_id
  ssh_key_ids = [for k in scaleway_iam_ssh_key.admin : k.id]
  cloud_init  = var.cartography_cloud_init
  protected   = var.server_protected
  tags        = var.tags

  options {
    id = data.scaleway_baremetal_option.cartography_private_network[0].option_id
  }

  private_network {
    id = scaleway_vpc_private_network.main.id
  }
}

locals {
  # Private IPv4 of each server (private_ips may also contain IPv6 addresses).
  app_private_ip = try(
    [for p in scaleway_baremetal_server.app[0].private_ips : p.address if !strcontains(p.address, ":")][0],
    null
  )
  cartography_private_ip = try(
    [for p in scaleway_baremetal_server.cartography[0].private_ips : p.address if !strcontains(p.address, ":")][0],
    null
  )
}
