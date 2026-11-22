output "private_network_id" {
  description = "Private Network ID."
  value       = scaleway_vpc_private_network.main.id
}

output "gateway_public_ip" {
  description = "Public Gateway IP (SSH bastion host)."
  value       = scaleway_vpc_public_gateway_ip.gw.address
}

output "bastion_ssh_port" {
  description = "SSH bastion port."
  value       = var.bastion_port
}

output "bastion_ssh_command" {
  description = "SSH command to reach the app server through the bastion."
  value       = local.app_private_ip == null ? null : "ssh -J bastion@${scaleway_vpc_public_gateway_ip.gw.address}:${var.bastion_port} ${var.server_ssh_user}@${local.app_private_ip}"
}

output "app_server_private_ip" {
  description = "App server private IPv4 (null if not created)."
  value       = local.app_private_ip
}

output "cartography_server_private_ip" {
  description = "Cartography server private IPv4 (null if not created)."
  value       = local.cartography_private_ip
}

output "app_server_public_ipv4" {
  description = "Public IPv4 of the app server. Bare metal always gets one: protect it with a host firewall."
  value       = try(scaleway_baremetal_server.app[0].ipv4[0].address, null)
}

output "lb_mode" {
  description = "tls-on-lb (Let's Encrypt certificate on the load balancer) or tcp-passthrough (TLS on the app server)."
  value       = local.lb_tls_enabled ? "tls-on-lb" : "tcp-passthrough"
}

output "lb_certificate_id" {
  description = "ID of the Let's Encrypt certificate of the load balancer (null without lb_domain_names)."
  value       = one(scaleway_lb_certificate.main[*].id)
}

output "lb_dns_records_hint" {
  description = "DNS records to create at your DNS provider (LWS) BEFORE adding lb_domain_names."
  value       = [for d in var.lb_domain_names : "${d}. A ${scaleway_lb_ip.lb.ip_address}"]
}

output "lb_public_ip" {
  description = "Public IP of the load balancer (point DNS here)."
  value       = scaleway_lb_ip.lb.ip_address
}

output "db_private_host" {
  description = "Private IP of the PostgreSQL instance."
  value       = scaleway_rdb_instance.main.private_network[0].ip
}

output "db_private_port" {
  description = "PostgreSQL port on the Private Network."
  value       = scaleway_rdb_instance.main.private_network[0].port
}

output "db_name" {
  description = "Application database name."
  value       = scaleway_rdb_database.app.name
}

output "db_app_user" {
  description = "Application database user."
  value       = scaleway_rdb_user.app.name
}

output "db_app_password" {
  description = "Application database password."
  value       = random_password.db_app.result
  sensitive   = true
}

output "db_admin_password" {
  description = "Administrator database password."
  value       = random_password.db_admin.result
  sensitive   = true
}

output "db_ssh_tunnel_hint" {
  description = "SSH tunnel for database inspection through the bastion and the app server."
  value       = local.app_private_ip == null ? null : "ssh -J bastion@${scaleway_vpc_public_gateway_ip.gw.address}:${var.bastion_port} -L 5432:${scaleway_rdb_instance.main.private_network[0].ip}:${scaleway_rdb_instance.main.private_network[0].port} ${var.server_ssh_user}@${local.app_private_ip}"
}

output "registry_endpoint" {
  description = "Container Registry endpoint."
  value       = scaleway_registry_namespace.main.endpoint
}

output "documents_bucket_name" {
  description = "Documents bucket name."
  value       = scaleway_object_bucket.documents.name
}

output "backups_bucket_name" {
  description = "Backups bucket name (versioned)."
  value       = scaleway_object_bucket.backups.name
}

output "bucket_endpoint" {
  description = "S3 API endpoint of the documents bucket."
  value       = scaleway_object_bucket.documents.api_endpoint
}

output "app_api_access_key" {
  description = "Access key of the application API key."
  value       = scaleway_iam_api_key.app.access_key
}

output "app_api_secret_key" {
  description = "Secret key of the application API key."
  value       = scaleway_iam_api_key.app.secret_key
  sensitive   = true
}

output "secrets" {
  description = "Secret Manager secrets created by this stack: name => { id, path }."
  value       = { for k, s in scaleway_secret.main : k => { id = s.id, path = s.path } }
}

output "secrets_read_hint" {
  description = "How to read a secret with the scw CLI."
  value       = var.secrets_enabled ? "scw secret version access-by-path secret-path=${local.secrets_path} secret-name=db-app revision=latest region=${var.region}" : null
}

output "generative_apis_usage_hint" {
  description = "How to call Generative APIs with the application API key."
  value       = "OpenAI-compatible. base_url=https://api.scaleway.ai/v1, header 'Authorization: Bearer <app_api_secret_key>'."
}
output "private_network_cidr" {
  description = "IPv4 subnet of the Private Network (used by the Ansible host firewall)."
  value       = var.private_network_cidr
}
output "cartography_server_public_ipv4" {
  description = "Public IPv4 of the cartography server. Bare metal always gets one: protect it with a host firewall."
  value       = try(scaleway_baremetal_server.cartography[0].ipv4[0].address, null)
}
output "app_server_private_vlan" {
  description = "VLAN ID of the Private Network on the app server NIC (unverified until the first apply)."
  value       = try(tolist(scaleway_baremetal_server.app[0].private_network)[0].vlan, null)
}
output "cartography_server_private_vlan" {
  description = "VLAN ID of the Private Network on the cartography server NIC (unverified until the first apply)."
  value       = try(tolist(scaleway_baremetal_server.cartography[0].private_network)[0].vlan, null)
}
