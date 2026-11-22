# Deployment guide – Proposal 7 (Scaleway)

This guide deploys one environment from scratch: network, database, storage and secrets with Terraform, then the Elastic Metal servers, then the server configuration with Ansible.

```
1. Prerequisites      5. Network, DB, storage, secrets (no servers yet)
2. Credentials        6. Check the database through the bastion
3. State storage      7. Order the servers
4. Variables          8. Configure the servers (Ansible)
                      9. Optional: HTTPS certificate on the load balancer
```

Rules that apply everywhere:
- Run every Terraform command through `./tf.sh <dev|prod> ...` from `infrastructure/terraform`. It selects the variables and the state of the environment, so dev and prod can never be mixed.
- Read each plan before applying it. Elastic Metal servers are **billed as soon as they are created**.
- Never put keys in `.tf` or `.tfvars` files.

| | Dev | Prod |
|---|---|---|
| Region / zone | `nl-ams` / `nl-ams-1` (Amsterdam 1) | `fr-par` / `fr-par-1` (Paris 1) |
| Variables | `envs/dev.tfvars` | `envs/prod.tfvars` |
| State backend settings | `envs/dev.backend.hcl` | `envs/prod.backend.hcl` |
| Scaleway project | dev project | prod project (separate) |
| Typical offers | `hourly` | `monthly` |

---

## 1. Prerequisites

On your laptop:
- Terraform >= 1.10 (state locking with the S3 backend), `curl`, `python3`, `ssh`, `psql`.
- Optional: the `scw` CLI, to read secrets.
- For step 8: Python 3.12 and Ansible, see [`../ansible/DEPLOYMENT.md`](../ansible/DEPLOYMENT.md).

In Scaleway:
- One project per environment.
- An API key for Terraform with these permission sets:

| Scope | Permission sets |
|---|---|
| The environment's project | Elastic Metal, VPC, Load Balancer, Managed Databases, Object Storage, Container Registry, `SecretManagerFullAccess` (or the matching `*FullAccess` sets) |
| **Organization** | `IAMManager` (creates the application identity, its policies and API key) |

IAM permission sets only work with Organization scope. A policy scoped to a project gives `insufficient permissions: create application`.

## 2. Credentials

```bash
export SCW_ACCESS_KEY=...
export SCW_SECRET_KEY=...
export SCW_DEFAULT_ORGANIZATION_ID=...
unset SCW_DEFAULT_PROJECT_ID     # the project comes from project_id in envs/<env>.tfvars

# Only for the remote S3 state backend (step 3, option A):
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"
```

If `SCW_DEFAULT_PROJECT_ID` stays exported, it overrides `project_id` and a dev run could land in another project. `tf.sh` unsets it and prints `>> note: ignoring exported SCW_DEFAULT_PROJECT_ID`.

## 3. State storage

The state holds the database passwords and API keys. Choose one option:

```bash
cd infrastructure/terraform

# Option A (recommended): remote state in Object Storage
#   First create a PRIVATE, versioned bucket in the console (dev: nl-ams, prod: fr-par).
cp backend.s3.tf.example backend.tf
cp envs/dev.backend.hcl.example envs/dev.backend.hcl     # set the bucket name

# Option B: local state, in states/<env>/terraform.tfstate (git-ignored)
cp backend.local.tf.example backend.tf
```

## 4. Variables

```bash
cp envs/dev.tfvars.example envs/dev.tfvars
```

Set at least:

| Variable | Value |
|---|---|
| `project_id` | the dev project ID (Console → Project settings) |
| `bastion_allowed_cidrs` | your public IPs, e.g. `["203.0.113.10/32"]` (must not be empty) |
| `ssh_public_keys` | one entry per admin: `"alice-laptop" = "ssh-ed25519 AAAA..."` |
| `bucket_suffix` | globally unique, different from prod |
| `app_offer_name`, `cartography_offer_name`, `offer_subscription_period` | your Elastic Metal offers and `hourly` / `monthly` |
| `create_app_server`, `create_cartography_server` | `false` for now (step 7 turns them on) |

### Private Network option of each offer

The servers sit in the Private Network, so each offer needs a Private Network option. Find its exact ID:

```bash
./find-pn-options.sh nl-ams-1 EM-A410X-SSD hourly
```

| Script output | What to do |
|---|---|
| an `option_id` | set `app_private_network_option_id = "<id>"` (same for `cartography_private_network_option_id`) |
| `NO Private Network option` | this offer can't be used: pick another one and run the script again |
| `No offer named ...` | the offer doesn't exist in that zone or with that subscription period |

## 5. Deploy the network, database, storage and secrets

With both `create_*_server = false`:

```bash
./tf.sh dev init
./tf.sh dev plan -out tfplan-dev
./tf.sh dev apply tfplan-dev
```

This creates: VPC and Private Network, Public Gateway with the SSH bastion (port 61000), load balancer (no backend yet), PostgreSQL (private endpoint only), buckets, registry, the application identity with its API key, and the secrets in Secret Manager.

Check in the plan:
- the region, zone and project are the expected ones;
- the PostgreSQL instance has no public endpoint (no `load_balancer` block);
- no `scaleway_baremetal_server` is created.

If an apply fails halfway, plan again (the old plan file is then stale) and apply the new plan.

## 6. Check the database through the bastion

The database is only reachable through the bastion. No server is needed.

```bash
./tf.sh dev output -raw gateway_public_ip    # e.g. 51.15.57.196
./tf.sh dev output -raw db_private_host      # e.g. 172.16.64.2
```

Add to `~/.ssh/config` (use the private key matching one of `ssh_public_keys`):

```
Host dev-db
  HostName <gateway_public_ip>
  Port 61000
  User bastion
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  LocalForward 127.0.0.1:15432 <db_private_host>:5432
  ExitOnForwardFailure yes
  ServerAliveInterval 30
```

```bash
ssh -N dev-db                         # terminal 1: keep it open

# terminal 2: password from Secret Manager (or ./tf.sh dev output -raw db_admin_password)
scw secret version access-by-path secret-path=/dev secret-name=db-admin \
  revision=latest field=password raw=true region=nl-ams
psql "host=127.0.0.1 port=15432 dbname=app user=rdb_admin sslmode=require"
```

The secrets are in Secret Manager under `/dev`: `db-admin`, `db-app`, `app-api-key`. See "Secrets in Secret Manager" in [`../README.md`](../README.md).

## 7. Order the servers

In `envs/dev.tfvars`, set `create_app_server = true` (and `create_cartography_server = true` if needed), then:

```bash
./tf.sh dev plan -out tfplan-dev     # check offer, zone and Private Network option of each server
./tf.sh dev apply tfplan-dev
```

The load balancer backends are created with the app server. Useful outputs afterwards:

```bash
./tf.sh dev output -raw app_server_public_ipv4    # first SSH access
./tf.sh dev output -raw app_server_private_ip     # e.g. 172.16.64.5
./tf.sh dev output -raw app_server_private_vlan   # e.g. 2116
./tf.sh dev output -raw lb_public_ip
```

## 8. Configure the servers (Ansible)

The servers come up with the public network only. Ansible configures the Private Network VLAN, the firewall, Docker and k3s. Follow [`../ansible/DEPLOYMENT.md`](../ansible/DEPLOYMENT.md). In short:

```bash
cd ../ansible
./gen-inventory.sh dev --mode public           # first access over the public IP
./run.sh dev network                           # VLAN interface (vlan<id> on eth0)
./gen-inventory.sh dev --mode bastion --force  # from now on, through the bastion
./run.sh dev base                              # firewall: SSH via bastion only, 80/443 from the Private Network
./run.sh dev site                              # Docker, k3s, cartography
```

Then connect to the server through the bastion: `ssh -J bastion@<gateway_public_ip>:61000 ubuntu@<app_server_private_ip>`.

## 9. Optional: HTTPS certificate on the load balancer

1. At your DNS provider (LWS), create an A record for each domain pointing to `lb_public_ip`. Check it with `dig +short app.example.com`.
2. In `envs/dev.tfvars`:
   ```hcl
   lb_domain_names = ["app.example.com"]
   ```
3. Plan and apply. `./tf.sh dev output lb_mode` then shows `tls-on-lb`.

The load balancer then terminates TLS with Let's Encrypt and sends plain HTTP to the app server on port 80. Without `lb_domain_names` it stays a TCP pass-through, and TLS is handled on the server. Details: "Load balancer certificate" in [`../README.md`](../README.md).

## 10. Final checks

```bash
./tf.sh dev output lb_mode
curl -I http://<lb_public_ip>              # or https://<domain> with a certificate
ssh -N dev-db                              # database through the bastion
ssh -J bastion@<gateway_public_ip>:61000 ubuntu@<app_server_private_ip>
```

The load balancer marks its backend down until something listens on port 80 (and 443 in pass-through mode) on the app server, for example Traefik in k3s.

Still manual, outside Terraform:
- WAF in front of the load balancer (Cloudflare or Scaleway Edge Services).
- The cartography service itself, and backups of its local data to the backups bucket.

## 11. Prod

Same steps with `prod`, in Paris and with a separate project:

```bash
cp envs/prod.tfvars.example envs/prod.tfvars
cp envs/prod.backend.hcl.example envs/prod.backend.hcl    # option A
./tf.sh prod plan -out tfplan-prod
./tf.sh prod apply tfplan-prod
```

Use a different project, state bucket, `bucket_suffix`, `bastion_allowed_cidrs` review and Ansible vault password from dev. In the prod example, the servers, the database and the secrets are protected against deletion.

## Troubleshooting

| Error | Cause and fix |
|---|---|
| `Multiple variable sources detected ... SCW_DEFAULT_PROJECT_ID` | `unset SCW_DEFAULT_PROJECT_ID`; the project comes from `project_id`. |
| `insufficient permissions: read project` | Set `project_id` in `envs/<env>.tfvars`. |
| `insufficient permissions: create application` | The API key needs `IAMManager` with **Organization** scope (step 1). |
| `insufficient permissions` on `scaleway_secret` | Add `SecretManagerFullAccess` on the project, or set `secrets_enabled = false`. |
| `attaching a private network requires enabling an offer-compatible private network option` | Set the option ID from `find-pn-options.sh` (step 4), or choose another offer. |
| `Saved plan is stale` | The state changed since the plan (e.g. a failed apply). Plan again, then apply the new plan. |
| `Backend initialization required` | Always use `./tf.sh <env> ...`; it re-initialises the right backend on every run. |
| `ssh dev-db` times out | Your public IP isn't in `bastion_allowed_cidrs`. |
| `Permission denied (publickey)` at the bastion | Your key isn't in `ssh_public_keys`; add it and apply again. |
| SSH to the server's private IP times out | The VLAN isn't configured yet: run the Ansible `network` role (step 8). |
| Load balancer certificate in error | The domain doesn't resolve to `lb_public_ip` yet. Fix the DNS record and apply again. |

## Tearing down dev

- **Servers**: set both `create_*_server = false`, then plan and apply. The monthly fee or commitment of the offer may still apply.
- **Database**: `prevent_destroy = true` in `database.tf` blocks any destroy. Set it to `false` deliberately, only for dev.
- **Buckets**: dev uses `buckets_force_destroy = true`; prod keeps `false`.
- **Secrets**: dev secrets are not protected; prod sets `secrets_protected = true`, which must be turned off before deleting.
