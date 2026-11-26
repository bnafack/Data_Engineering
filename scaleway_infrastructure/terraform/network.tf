resource "scaleway_vpc" "main" {
  name = "${var.name_prefix}-vpc"
  tags = var.tags
}

resource "scaleway_vpc_private_network" "main" {
  name   = "${var.name_prefix}-pn"
  vpc_id = scaleway_vpc.main.id
  tags   = var.tags

  ipv4_subnet {
    subnet = var.private_network_cidr
  }
}

# The IAM SSH keys serve the bare metal servers AND the gateway bastion.
# One key is created per entry of var.ssh_public_keys.
resource "scaleway_iam_ssh_key" "admin" {
  for_each = var.ssh_public_keys

  name       = each.key
  public_key = each.value
}

# Public Gateway with the SSH bastion. Optional (create_public_gateway), e.g. off in dev to save about 23 EUR/month.
resource "scaleway_vpc_public_gateway_ip" "gw" {
  count = var.create_public_gateway ? 1 : 0

  tags = var.tags
}

resource "scaleway_vpc_public_gateway" "gw" {
  count = var.create_public_gateway ? 1 : 0

  name              = "${var.name_prefix}-gw"
  type              = var.gateway_type
  ip_id             = scaleway_vpc_public_gateway_ip.gw[0].id
  bastion_enabled   = true
  bastion_port      = var.bastion_port
  allowed_ip_ranges = var.bastion_allowed_cidrs
  refresh_ssh_keys  = sha256(join("\n", sort(values(var.ssh_public_keys))))
  tags              = var.tags

  depends_on = [scaleway_iam_ssh_key.admin]

  lifecycle {
    precondition {
      condition     = length(var.bastion_allowed_cidrs) > 0
      error_message = "bastion_allowed_cidrs must contain at least one CIDR so the SSH bastion is never open to the world."
    }
  }
}

resource "scaleway_vpc_gateway_network" "gw" {
  count = var.create_public_gateway ? 1 : 0

  gateway_id         = scaleway_vpc_public_gateway.gw[0].id
  private_network_id = scaleway_vpc_private_network.main.id
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }
}
