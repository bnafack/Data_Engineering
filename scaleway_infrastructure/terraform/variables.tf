# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "project_id" {
  description = "Scaleway project ID of this environment. Set it in envs/<env>.tfvars (takes the place of SCW_DEFAULT_PROJECT_ID, which must not be exported)."
  type        = string
  default     = null
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway availability zone (fr-par-1 = Paris 1, nl-ams-1 = Amsterdam 1). Must belong to var.region."
  type        = string
  default     = "fr-par-1"

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "zone must belong to region (for example region nl-ams with zone nl-ams-1)."
  }
}

variable "name_prefix" {
  description = "Prefix used in resource names."
  type        = string
  default     = "proposal7"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 2-20 characters: lowercase letters, digits, hyphens."
  }
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = list(string)
  default     = ["proposal7", "terraform"]
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "private_network_cidr" {
  description = "IPv4 subnet of the Private Network."
  type        = string
  default     = "172.16.64.0/22"

  validation {
    condition     = can(cidrnetmask(var.private_network_cidr))
    error_message = "private_network_cidr must be a valid IPv4 CIDR."
  }
}

variable "create_public_gateway" {
  description = <<-EOT
    Create the Public Gateway (SSH bastion and NAT). Billed per hour (about 23 EUR/month).
    false = no bastion: reach the database and the servers through the app server's public IP instead
    (SSH allowed only from your admin IPs). Whether the Private Network address assignment (DHCP) works
    without a gateway is not verified: use network_use_dhcp=false with a static address if it does not.
  EOT
  type        = bool
  default     = true
}

variable "create_load_balancer" {
  description = <<-EOT
    Create the load balancer, its public IP, backends, frontends and certificate. Billed per hour (about
    20 EUR/month). false = no public entry point through the load balancer: test the app through the
    server's public IP (open ports 80/443 to your admin IPs in the host firewall). Incompatible with lb_domain_names.
  EOT
  type        = bool
  default     = true
}

variable "gateway_type" {
  description = "Public Gateway type."
  type        = string
  default     = "VPC-GW-S"
}

variable "bastion_port" {
  description = "SSH bastion port on the Public Gateway."
  type        = number
  default     = 61000

  validation {
    condition     = var.bastion_port >= 1 && var.bastion_port <= 65535
    error_message = "bastion_port must be between 1 and 65535."
  }
}

variable "bastion_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the SSH bastion (e.g. [\"203.0.113.10/32\"]). Must not be empty."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.bastion_allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry of bastion_allowed_cidrs must be a valid IPv4 CIDR."
  }
}

# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------
variable "ssh_public_keys" {
  description = "Admin SSH public keys, as a map of name => OpenSSH public key. Each one is registered in IAM and authorised on the servers and the bastion."
  type        = map(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "ssh_public_keys must contain at least one key."
  }

  validation {
    condition = alltrue([
      for k in values(var.ssh_public_keys) :
      startswith(trimspace(k), "ssh-") || startswith(trimspace(k), "ecdsa-")
    ])
    error_message = "Every entry of ssh_public_keys must be an OpenSSH public key (ssh-ed25519, ssh-rsa, ecdsa-...)."
  }
}

variable "server_ssh_user" {
  description = "Default SSH user on the servers (used in output hints only)."
  type        = string
  default     = "ubuntu"
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
variable "lb_type" {
  description = "Load Balancer type."
  type        = string
  default     = "LB-S"
}

variable "secrets_enabled" {
  description = "Store the generated secrets (database passwords, application API key) in Scaleway Secret Manager."
  type        = bool
  default     = true
}

variable "secrets_path" {
  description = "Secret Manager folder for this environment. Null = \"/<name_prefix>\" (e.g. /dev)."
  type        = string
  default     = null

  validation {
    condition     = var.secrets_path == null || can(regex("^/([A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*)?$", coalesce(var.secrets_path, "/")))
    error_message = "secrets_path must start with \"/\", e.g. \"/dev\" or \"/proposal7/dev\"."
  }
}

variable "secrets_protected" {
  description = "Protect the secrets against deletion (a protected secret cannot be deleted until protection is removed). Recommended for prod."
  type        = bool
  default     = false
}

variable "secrets_grant_app_access" {
  description = "Allow the application identity (IAM application) to read the secrets of the project."
  type        = bool
  default     = true
}

variable "lb_domain_names" {
  description = <<-EOT
    Domain names for a Let's Encrypt certificate on the load balancer. Empty = no certificate, TCP pass-through
    (TLS on the app server). Not empty = TLS terminated on the load balancer: the first name is the common name,
    the others are alternative names. Every name must already resolve to lb_public_ip (A record at your DNS
    provider) before terraform apply, otherwise Let's Encrypt cannot validate it.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.lb_domain_names) == 0 || var.create_load_balancer
    error_message = "lb_domain_names needs the load balancer: set create_load_balancer = true or empty lb_domain_names."
  }

  validation {
    condition = alltrue([
      for d in var.lb_domain_names :
      can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", d))
    ])
    error_message = "lb_domain_names must be lowercase fully qualified domain names, e.g. app.example.com (no wildcard, no scheme)."
  }

  validation {
    condition     = length(var.lb_domain_names) == length(distinct(var.lb_domain_names))
    error_message = "lb_domain_names must not contain duplicates."
  }
}

variable "lb_health_check_http_path" {
  description = "With a certificate (HTTP mode): path of an HTTP health check that returns 200, e.g. \"/healthz\". Null = TCP check."
  type        = string
  default     = null

  validation {
    condition     = var.lb_health_check_http_path == null || startswith(coalesce(var.lb_health_check_http_path, "/"), "/")
    error_message = "lb_health_check_http_path must start with \"/\"."
  }
}

variable "app_http_port" {
  description = "Backend port on the app server for HTTP traffic."
  type        = number
  default     = 80
}

variable "app_https_port" {
  description = "Backend port on the app server for HTTPS traffic."
  type        = number
  default     = 443
}

# ---------------------------------------------------------------------------
# Bare metal servers (billed as soon as created)
# ---------------------------------------------------------------------------
variable "create_app_server" {
  description = "Create the application Elastic Metal server (and the LB backends pointing to it)."
  type        = bool
  default     = true
}

variable "create_cartography_server" {
  description = "Create the cartography Elastic Metal server."
  type        = bool
  default     = true
}

variable "app_offer_name" {
  description = "Elastic Metal offer for the application server."
  type        = string
  default     = "EM-A410X-SSD"
}

variable "cartography_offer_name" {
  description = "Elastic Metal offer for the cartography server. Alternative: EM-B212X-SSD."
  type        = string
  default     = "EM-B420E-NVMe"
}

variable "app_private_network_option_name" {
  description = "Private Network option name for the app server offer (to verify)."
  type        = string
  default     = "Private Networks 1 Gbps feature"
}

variable "cartography_private_network_option_name" {
  description = "Private Network option name for the cartography server. Use \"Private Networks 1 Gbps feature\" with EM-B212X-SSD."
  type        = string
  default     = "Private Networks 10 Gbps feature"
}

# Recommended: set the option ID instead of the name. Options are looked up by
# name across the whole zone, and several options can share a name; the
# provider then rejects one that is not in the offer's own option list
# ("attaching a private network requires enabling an offer-compatible private
# network option"). Find the right ID with: ./find-pn-options.sh <zone> <offer>
variable "app_private_network_option_id" {
  description = "Private Network option ID of the app server offer (from find-pn-options.sh). Overrides app_private_network_option_name when set."
  type        = string
  default     = null

  validation {
    condition     = var.app_private_network_option_id == null || can(regex("^([a-z]{2}-[a-z]{3}-[0-9]/)?[0-9a-f-]{36}$", var.app_private_network_option_id))
    error_message = "app_private_network_option_id must be a UUID (optionally prefixed with the zone, e.g. nl-ams-1/<uuid>)."
  }
}

variable "cartography_private_network_option_id" {
  description = "Private Network option ID of the cartography server offer (from find-pn-options.sh). Overrides cartography_private_network_option_name when set."
  type        = string
  default     = null

  validation {
    condition     = var.cartography_private_network_option_id == null || can(regex("^([a-z]{2}-[a-z]{3}-[0-9]/)?[0-9a-f-]{36}$", var.cartography_private_network_option_id))
    error_message = "cartography_private_network_option_id must be a UUID (optionally prefixed with the zone, e.g. nl-ams-1/<uuid>)."
  }
}

variable "os_name" {
  description = "Operating system name."
  type        = string
  default     = "Ubuntu"
}

variable "os_version" {
  description = "Operating system version (exact string as listed by Scaleway)."
  type        = string
  default     = "26.04 LTS (Resolute Raccoon)"
}

variable "offer_subscription_period" {
  description = "Subscription period used to look up offers."
  type        = string
  default     = "monthly"
}

variable "app_cloud_init" {
  description = "Optional cloud-init for the app server (only if the offer supports it)."
  type        = string
  default     = null
}

variable "cartography_cloud_init" {
  description = "Optional cloud-init for the cartography server (only if the offer supports it)."
  type        = string
  default     = null
}

variable "server_protected" {
  description = "Enable protection against accidental deletion on the servers."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Managed PostgreSQL
# ---------------------------------------------------------------------------
variable "db_engine" {
  description = "Database engine."
  type        = string
  default     = "PostgreSQL-16"
}

variable "db_node_type" {
  description = "Database node type (check compatibility with sbs_15k)."
  type        = string
  default     = "db-play2-pico"
}

variable "db_volume_type" {
  description = "Database volume type. sbs_15k = 15k IOPS block storage."
  type        = string
  default     = "sbs_15k"

  validation {
    condition     = contains(["sbs_5k", "sbs_15k"], var.db_volume_type)
    error_message = "db_volume_type must be sbs_5k or sbs_15k."
  }
}

variable "db_volume_size_gb" {
  description = "Database volume size in GB."
  type        = number
  default     = 50

  validation {
    condition     = var.db_volume_size_gb >= 10
    error_message = "db_volume_size_gb must be at least 10."
  }
}

variable "db_is_ha" {
  description = "Enable high availability (standby node)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Number of days daily backups are kept."
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 90
    error_message = "db_backup_retention_days must be between 1 and 90."
  }
}

variable "db_backup_frequency_hours" {
  description = "Backup frequency in hours (24 = daily)."
  type        = number
  default     = 24
}

variable "db_encryption_at_rest" {
  description = "Enable encryption at rest."
  type        = bool
  default     = true
}

variable "db_admin_user" {
  description = "Administrator user of the instance."
  type        = string
  default     = "rdb_admin"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "app"
}

variable "db_app_user" {
  description = "Application database user (non-admin)."
  type        = string
  default     = "app_user"
}

# ---------------------------------------------------------------------------
# Storage and registry
# ---------------------------------------------------------------------------
variable "bucket_suffix" {
  description = "Unique suffix for bucket names (bucket names are global)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.bucket_suffix))
    error_message = "bucket_suffix must be 3-30 characters: lowercase letters, digits, hyphens."
  }
}

variable "documents_bucket_name" {
  description = "Documents bucket name. Null = <name_prefix>-documents-<bucket_suffix>."
  type        = string
  default     = null
}

variable "backups_bucket_name" {
  description = "Backups bucket name. Null = <name_prefix>-backups-<bucket_suffix>."
  type        = string
  default     = null
}

variable "registry_namespace_name" {
  description = "Container Registry namespace. Null = <name_prefix>-registry-<bucket_suffix>."
  type        = string
  default     = null
}

variable "buckets_force_destroy" {
  description = "Allow destroying non-empty buckets."
  type        = bool
  default     = false
}
