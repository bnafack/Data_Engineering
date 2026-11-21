# Proposal 7 infrastructure (Scaleway, fr-par-1)

Terraform for the design in [`architecture/proposal-7-architecture.svg`](../architecture/proposal-7-architecture.svg).
Code lives in `terraform/`. Nothing here has been applied; `plan` and `apply` were never run.

## Architecture

- One VPC and one Private Network (`172.16.64.0/22` by default).
- Public Gateway with an SSH bastion (port 61000), restricted to `bastion_allowed_cidrs`, plus masquerade for outbound traffic.
- L4 Load Balancer (TCP 80/443 pass-through, TCP health check). Its backends are the **private IP** of the app server only. TLS is terminated on the app server.
- App server: Elastic Metal `EM-A410X-SSD` (k3s, Docker, Argo CD, installed with Ansible).
- Cartography server: Elastic Metal `EM-B420E-NVMe` + 10 Gbps Private Network option. Alternative: `EM-B212X-SSD` + 1 Gbps option.
- Managed PostgreSQL on the Private Network only (no public endpoint), 15k IOPS volume (`sbs_15k`), daily backups with configurable retention.
- Object Storage: a private documents bucket and a private, versioned backups bucket.
- Private Container Registry namespace.
- IAM application with three policies (object storage, registry pull, Generative APIs) and one API key.
- No Redis. No Dedibox.

## Prerequisites

- Terraform >= 1.9.0
- A Scaleway account, project and an API key able to create these resources
- An SSH key pair

## Authentication

Never put credentials in `.tf` or `.tfvars` files. Export them:

```bash
export SCW_ACCESS_KEY=...
export SCW_SECRET_KEY=...
export SCW_DEFAULT_PROJECT_ID=...
export SCW_DEFAULT_ORGANIZATION_ID=...
```

## Usage

Always run Terraform through `tf.sh`, which selects the right variables and state for the environment (see "Environments: dev and prod" below).

```bash
cd infrastructure/terraform
cp envs/dev.tfvars.example envs/dev.tfvars      # edit: project_id, bastion_allowed_cidrs, ssh_public_keys, bucket_suffix
./tf.sh dev init
./tf.sh dev plan -out tfplan-dev
./tf.sh dev apply tfplan-dev
./tf.sh dev output -raw db_app_password
```

`terraform.tfvars.example` is still available as a single-environment reference listing every variable.

Tip: first run with `create_app_server=false` and `create_cartography_server=false` (the dev default) to deploy everything except the paid servers. Note that the LB backends are only created when the app server exists.

## Environments: dev and prod

Provider settings (`region`, `zone`, `project_id`) are set once in `providers.tf` and inherited by every resource, so one deployment targets exactly one region and one Scaleway project. Dev and prod are therefore two separate deployments of the same code, each with its own variables and its own state.

| | Dev | Prod |
|---|---|---|
| Variables | `envs/dev.tfvars` | `envs/prod.tfvars` |
| Remote state (optional) | `envs/dev.backend.hcl` (key `proposal7/dev/...`) | `envs/prod.backend.hcl` (key `proposal7/prod/...`) |
| Scaleway project | dev project (`project_id`) | prod project, separate from dev |
| Name prefix | `dev` | `prod` |
| Private Network CIDR | `172.16.64.0/22` | `172.16.68.0/22` |
| Bare-metal servers | off by default | on, `server_protected = true` |
| PostgreSQL | small, `sbs_5k`, no HA, 7 days of backups | `sbs_15k`, HA, 30 days of backups |
| Buckets `force_destroy` | `true` | `false` |

Setup:

```bash
cd infrastructure/terraform
cp envs/dev.tfvars.example  envs/dev.tfvars
cp envs/prod.tfvars.example envs/prod.tfvars

# State storage: choose ONE (backend.tf is required by tf.sh)

# Option A, recommended: remote state in Object Storage, one state key per environment
cp backend.s3.tf.example backend.tf
cp envs/dev.backend.hcl.example  envs/dev.backend.hcl
cp envs/prod.backend.hcl.example envs/prod.backend.hcl
# edit the bucket names in both .backend.hcl files (private, encrypted buckets)

# Option B: local state, one file per environment (states/<env>/terraform.tfstate)
cp backend.local.tf.example backend.tf
```

Commands (`tf.sh` re-selects the environment's state on every run, so a command cannot hit the other environment's state):

```bash
./tf.sh dev  plan -out tfplan-dev
./tf.sh dev  apply tfplan-dev
./tf.sh prod plan -out tfplan-prod
./tf.sh prod apply tfplan-prod
```

State handling (no Terraform workspaces are used; each environment has its own state file or key):
- `backend.tf` from `backend.s3.tf.example`: remote S3 state. The bucket and key come from `envs/<env>.backend.hcl`, with keys `proposal7/dev/...` and `proposal7/prod/...`.
- `backend.tf` from `backend.local.tf.example`: local state in `states/<env>/terraform.tfstate` (git-ignored). Convenient for a first try, but the state holds the database passwords and stays on your machine.
- `tf.sh` stops with an explanation if `backend.tf` is missing.
- To move from local to remote state later: replace `backend.tf` with the S3 version, then run `terraform init -migrate-state -backend-config=envs/<env>.backend.hcl` by hand (not through `tf.sh`, which uses `-reconfigure` and would not copy the state). Do it one environment at a time.

Things to know:
- Use a separate Scaleway project (and API key) per environment: IAM, billing and quotas are isolated, so a dev mistake cannot reach prod.
- Object Storage bucket names are global: `bucket_suffix` must differ between environments.
- `prevent_destroy` on the database applies to both environments; set it to `false` temporarily to tear down dev.
- The prod database node type (`DB-POP2-2C-8G`) and its compatibility with `sbs_15k` and HA are unverified.
- Never run a plain `terraform plan` or `apply` without `tf.sh`: it would use whichever state was initialised last.

## Bare-metal billing warning

Elastic Metal servers are billed immediately on creation (monthly fee, possibly a commitment). Check the console order summary before `apply`.

## Estimated monthly cost (EUR, excl. VAT, approximate)

| Item | Price |
|---|---|
| App server EM-A410X-SSD | 54.99 |
| Cartography EM-B420E-NVMe + 10 Gbps option | 159.99 + 19.99 = 179.98 |
| Alternative: EM-B212X-SSD + 1 Gbps option | 115.99 + 9.99 = 125.98 |
| Load Balancer, Public Gateway, managed PostgreSQL, storage, registry | extra, see Scaleway pricing |

## Database access (inspection and administration)

The database has no public endpoint. Reach it through the bastion and the app server:

```
Host proposal7-app
  HostName <app_server_private_ip>
  User ubuntu
  ProxyJump bastion@<gateway_ip>:61000
  LocalForward 5432 <db_private_host>:5432
```

Then `ssh proposal7-app` and, in another terminal, `psql -h 127.0.0.1 -U app_user app`. The output `db_ssh_tunnel_hint` prints the equivalent command. Passwords: `terraform output -raw db_app_password` / `db_admin_password`.

## Switching the cartography server

```hcl
cartography_offer_name                  = "EM-B212X-SSD"
cartography_private_network_option_name = "Private Networks 1 Gbps feature"
```

## Post-provision steps
Done by Ansible, see [Ansible: configure servers and install k3s](#ansible-configure-servers-and-install-k3s):
- Private Network VLAN interface (netplan/DHCP): role `network`, opt-in and unverified. The pushed default route does not replace the public NIC route.
- Elastic Metal servers always have a public IPv4. Terraform cannot remove it: role `base` configures the host firewall (SSH only from admin CIDRs and the Private Network, 80/443 only from the Private Network).
- Docker, k3s and Argo CD: roles `docker`, `k3s`, `argocd`. Cloud-init (`app_cloud_init`) is optional and only for a tiny first-boot file.
## Ansible: configure servers and install k3s
After `terraform apply` has created the servers, [`ansible/`](ansible/README.md) applies a baseline (packages, SSH hardening, fail2ban, firewall), optionally configures the Private Network interface, installs Docker, a pinned single-server k3s (app server only) and, optionally, Argo CD. Dev and prod have separate inventories and variables, like Terraform. Terraform outputs stay the source of truth for IPs.
```bash
cd infrastructure/terraform && ./tf.sh dev apply tfplan-dev     # servers must exist
cd ../ansible
ansible-galaxy collection install -r requirements.yml -p .ansible/collections
./gen-inventory.sh dev --mode public                            # first run: public IPs, admin CIDRs only
./run.sh dev base                                               # then optionally: ./run.sh dev network
./gen-inventory.sh dev --mode bastion --force                   # afterwards: through the SSH bastion
./run.sh dev site
```
`gen-inventory.sh` reads four new Terraform outputs (`private_network_cidr`, `cartography_server_public_ipv4`, `app_server_private_vlan`, `cartography_server_private_vlan`). They were never applied or tested.
## Security notes

- Database passwords and the API secret key are stored in Terraform state. Use a private, encrypted remote backend (`backend.s3.tf.example`) and restrict access.
- Sensitive outputs: `db_app_password`, `db_admin_password`, `app_api_secret_key`.
- IAM permission sets are project-scoped; they cannot be limited to a single bucket.

## Out of scope

- WAF (Cloudflare or Scaleway Edge Services)
- DNS at LWS (point your records to `lb_public_ip`)
- Argo CD application manifests (the Argo CD, k3s and Docker bootstrap is in `ansible/`)
- The old Dedibox

## To verify before the first apply

1. Private Network option names (`scw baremetal option list zone=fr-par-1`), especially for EM-A410X-SSD.
2. That entry-range offers can join a Private Network and act as LB backends.
3. OS strings (`scw baremetal os list`); the default `26.04 LTS (Resolute Raccoon)` comes from the order screen.
4. Cloud-init support on the chosen offers.
5. Public IPv4 on bare metal cannot be disabled (see above).
6. Network config on the servers after attaching the Private Network.
7. DB node type `db-play2-pico` with `sbs_15k` and engine string `PostgreSQL-16` (`scw rdb node-type list`, `scw rdb engine list`).
8. Gateway type `VPC-GW-S` and LB type `LB-S` in fr-par-1.
9. IAM permission set names, notably `GenerativeApisFullAccess` (a narrower one may exist).
10. Prices are approximate.
11. SSH user on the servers (`server_ssh_user`, default `ubuntu`).

## Database protection against destruction

`scaleway_rdb_instance.main` and `scaleway_rdb_database.app` have `lifecycle { prevent_destroy = true }` in `terraform/database.tf`.

- Terraform refuses any plan that would delete or replace them. This includes `terraform destroy` (the whole destroy fails), and changes that force a replacement such as the engine or `encryption_at_rest`. In-place changes (volume size, node type, backup schedule) still work.
- The Scaleway provider (2.93.0) has no deletion-protection flag on the PostgreSQL instance, and `prevent_destroy` must be a literal, so it cannot be a variable. It only protects against Terraform, not against someone deleting the instance in the console or with the CLI.
- To delete the database on purpose: set `prevent_destroy = false` in `database.tf`, run `terraform apply`, then run the destroy or removal. Set it back to `true` afterwards if the resource still exists.
- Complement it outside Terraform: give day-to-day users read-only database permissions in IAM and keep full access to a few people, keep `db_backup_retention_days` at 7 or more, and regularly export a `pg_dump` to the backups bucket. Confirm in the console whether automatic backups are kept after an instance is deleted (not verified).
- The object storage buckets are already protected from deletion while non-empty, because `buckets_force_destroy` defaults to `false`.
