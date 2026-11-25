# Load balancer in front of the app server (private IP only). Two modes:
#
#   lb_domain_names = []  (default)  L4 TCP pass-through on 80/443. TLS is terminated on the app server.
#   lb_domain_names = ["app.example.com", ...]
#                                    TLS terminated on the load balancer with a Let's Encrypt certificate.
#                                    Frontends 80 and 443 forward plain HTTP to the app server (app_http_port)
#                                    over the Private Network. The DNS records must point to lb_public_ip
#                                    BEFORE the certificate is created (see README "Load balancer certificate").

locals {
  lb_enabled     = var.create_load_balancer
  lb_tls_enabled = local.lb_enabled && length(var.lb_domain_names) > 0

  # TCP pass-through (no certificate)
  lb_tcp_ports = local.lb_enabled && var.create_app_server && !local.lb_tls_enabled ? {
    http  = var.app_http_port
    https = var.app_https_port
  } : {}

  # TLS on the load balancer: public port => use the certificate or not
  lb_http_frontends = local.lb_enabled && var.create_app_server && local.lb_tls_enabled ? {
    http  = { port = 80, tls = false }
    https = { port = 443, tls = true }
  } : {}
}

resource "scaleway_lb_ip" "lb" {
  count = local.lb_enabled ? 1 : 0

  zone = var.zone
  tags = var.tags
}

resource "scaleway_lb" "main" {
  count = local.lb_enabled ? 1 : 0

  name   = "${var.name_prefix}-lb"
  type   = var.lb_type
  zone   = var.zone
  ip_ids = [scaleway_lb_ip.lb[0].id]
  tags   = var.tags

  private_network {
    private_network_id = scaleway_vpc_private_network.main.id
  }
}

# ---------------------------------------------------------------------------
# Mode 1: TCP pass-through
# ---------------------------------------------------------------------------
resource "scaleway_lb_backend" "tcp" {
  for_each = local.lb_tcp_ports

  lb_id                  = scaleway_lb.main[0].id
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
  for_each = local.lb_tcp_ports

  lb_id        = scaleway_lb.main[0].id
  backend_id   = scaleway_lb_backend.tcp[each.key].id
  name         = "${var.name_prefix}-${each.key}"
  inbound_port = each.value
}

# ---------------------------------------------------------------------------
# Mode 2: TLS on the load balancer (Let's Encrypt)
# ---------------------------------------------------------------------------
resource "scaleway_lb_certificate" "main" {
  count = local.lb_tls_enabled ? 1 : 0

  lb_id = scaleway_lb.main[0].id
  # The name changes with the domains, so a new certificate can be created before the old one is removed.
  name = "${var.name_prefix}-${substr(sha1(join(",", var.lb_domain_names)), 0, 8)}"

  letsencrypt {
    common_name              = var.lb_domain_names[0]
    subject_alternative_name = slice(var.lb_domain_names, 1, length(var.lb_domain_names))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "scaleway_lb_backend" "http" {
  count = length(local.lb_http_frontends) > 0 ? 1 : 0

  lb_id                  = scaleway_lb.main[0].id
  name                   = "${var.name_prefix}-http"
  forward_protocol       = "http"
  forward_port           = var.app_http_port
  forward_port_algorithm = "roundrobin"
  server_ips             = [local.app_private_ip]

  health_check_delay       = "10s"
  health_check_timeout     = "5s"
  health_check_max_retries = 3
  on_marked_down_action    = "none"

  # TCP check by default: an HTTP check on "/" fails while no app answers there (e.g. Traefik returns 404).
  dynamic "health_check_tcp" {
    for_each = var.lb_health_check_http_path == null ? [1] : []
    content {}
  }

  dynamic "health_check_http" {
    for_each = var.lb_health_check_http_path == null ? [] : [1]
    content {
      uri  = var.lb_health_check_http_path
      code = 200
    }
  }
}

resource "scaleway_lb_frontend" "http" {
  for_each = local.lb_http_frontends

  lb_id           = scaleway_lb.main[0].id
  backend_id      = scaleway_lb_backend.http[0].id
  name            = "${var.name_prefix}-${each.key}"
  inbound_port    = each.value.port
  certificate_ids = each.value.tls ? [scaleway_lb_certificate.main[0].id] : []
}
