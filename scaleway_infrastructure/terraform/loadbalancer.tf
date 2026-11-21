# L4 (TCP pass-through) load balancer. TLS is terminated on the app server.
# The backend is the private IP of the app server only.

locals {
  lb_ports = var.create_app_server ? {
    http  = var.app_http_port
    https = var.app_https_port
  } : {}
}

resource "scaleway_lb_ip" "lb" {
  zone = var.zone
  tags = var.tags
}

resource "scaleway_lb" "main" {
  name   = "${var.name_prefix}-lb"
  type   = var.lb_type
  zone   = var.zone
  ip_ids = [scaleway_lb_ip.lb.id]
  tags   = var.tags

  private_network {
    private_network_id = scaleway_vpc_private_network.main.id
  }
}

resource "scaleway_lb_backend" "tcp" {
  for_each = local.lb_ports

  lb_id                  = scaleway_lb.main.id
  name                   = "${var.name_prefix}-${each.key}"
  forward_protocol       = "tcp"
  forward_port           = each.value
  forward_port_algorithm = "roundrobin"
  server_ips             = [local.app_private_ip]

  health_check_delay       = "10s"
  health_check_timeout     = "5s"
  health_check_max_retries = 3
  on_marked_down_action    = "none"

  health_check_tcp {}
}

resource "scaleway_lb_frontend" "tcp" {
  for_each = local.lb_ports

  lb_id        = scaleway_lb.main.id
  backend_id   = scaleway_lb_backend.tcp[each.key].id
  name         = "${var.name_prefix}-${each.key}"
  inbound_port = each.value
}
