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
export SCW_DEFAULT_ORGANIZATION_ID=...
```

Do **not** export `SCW_DEFAULT_PROJECT_ID`. The project of each environment is set by `project_id` in `envs/<env>.tfvars`. When both are set, Terraform warns "Multiple variable sources detected" and the environment variable wins, so a dev run could silently land in the prod project. `tf.sh` unsets the variable when the tfvars file defines `project_id`.

The API key needs enough IAM rights to create IAM applications, policies and API keys (for example the `IAMManager` permission set) on top of the resource permissions. The code no longer needs the "read project" permission as long as `project_id` is set.

Versions of Terraform and of the providers are set in `terraform/providers.tf` (Terraform does not allow variables there). To change one, edit it, run `./tf.sh <env> init -upgrade` and commit `.terraform.lock.hcl`.

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
| Region / zone | `nl-ams` / `nl-ams-1` (Amsterdam 1) | `fr-par` / `fr-par-1` (Paris 1) |
| Scaleway project | dev project (`project_id`) | prod project, separate from dev |
| Name prefix | `dev` | `prod` |
| Private Network CIDR | `172.16.64.0/22` | `172.16.68.0/22` |
| Bare-metal servers | off by default; cartography offer EM-B212X-SSD (EM-B420E-NVMe is not in the AMS catalog) | on, `server_protected = true` |
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

## Load balancer certificate (optional)

By default the load balancer is a TCP pass-through on 80/443, and TLS is handled on the app server. Set `lb_domain_names` to let the load balancer terminate TLS with a free Let's Encrypt certificate instead.

| `lb_domain_names` | Mode | What happens |
|---|---|---|
| `[]` (default) | `tcp-passthrough` | 80 and 443 forwarded as TCP to the app server (`app_http_port`, `app_https_port`). |
| `["app.example.com", ...]` | `tls-on-lb` | Let's Encrypt certificate on the LB. Frontends 80 and 443 forward plain HTTP to the app server on `app_http_port`, over the Private Network. The first name is the common name, the others are alternative names. |

Steps (Let's Encrypt can only issue the certificate if the names already resolve to the load balancer):

1. Deploy without a domain and read the load balancer IP:
   ```bash
   ./tf.sh dev output -raw lb_public_ip
   ```
2. At your DNS provider (LWS), create an A record for each name pointing to that IP, e.g. `app.example.com. A 51.15.63.209`. Check that it resolves: `dig +short app.example.com`.
3. Set the names in `envs/<env>.tfvars`, then plan and apply:
   ```hcl
   lb_domain_names = ["app.example.com"]
   ```
4. Check: `./tf.sh dev output lb_mode` shows `tls-on-lb`, and `curl -I https://app.example.com` returns a response with a valid certificate.

Notes:
- The certificate is renewed automatically by Scaleway. Changing the names creates a new certificate before removing the old one.
- In `tls-on-lb` mode the app receives HTTP on `app_http_port`. Configure the app (or Traefik in k3s) to serve plain HTTP and trust `X-Forwarded-Proto`. Redirecting HTTP to HTTPS is up to the app.
- The health check is TCP by default. Set `lb_health_check_http_path` (e.g. `"/healthz"`) for an HTTP check that expects status 200.
- Switching modes replaces the backends and frontends, which causes a short interruption.
- Not verified: whether Let's Encrypt validation needs anything more than the A record (for example a reachable port 80 on the LB). If the certificate stays in an error state, check it in the console under Load Balancers → Certificates.

## Secrets in Secret Manager

With `secrets_enabled = true` (default), `terraform/secrets.tf` stores the secrets generated by this stack in Scaleway Secret Manager, in the folder `/<name_prefix>` (e.g. `/dev`, set with `secrets_path`):

| Secret | Type | Keys |
|---|---|---|
| `db-admin` | key_value | `username`, `password`, `host`, `port`, `dbname`, `sslmode` |
| `db-app` | key_value | same, for the application user |
| `app-api-key` | key_value | `access_key`, `secret_key`, `project_id` of the application identity |

Read them:

```bash
scw secret version access-by-path secret-path=/dev secret-name=db-app revision=latest region=nl-ams
# a single field:
scw secret version access-by-path secret-path=/dev secret-name=db-app revision=latest field=password raw=true region=nl-ams
```

`./tf.sh dev output secrets_read_hint` prints the command for your environment. In the console: Secret Manager → folder `/dev`.

- A new version is created automatically when a value changes (for example a rotated password). Old versions stay until you disable or delete them.
- `secrets_grant_app_access = true` adds a policy so the application identity (`<prefix>-app`) can read secrets with its API key (`SecretManagerReadOnly` + `SecretManagerSecretAccess`). IAM permission sets are project-scoped, so it can read **all** secrets of the project: keep one project per environment.
- `secrets_protected = true` (prod example) prevents deleting the secrets until protection is removed.
- The Terraform user needs Secret Manager rights (e.g. `SecretManagerFullAccess` on the project) in addition to the IAM rights already required.
- The values also remain in the Terraform state (they are produced by `random_password` and the IAM API key). The sensitive outputs (`db_app_password`, `db_admin_password`, `app_api_secret_key`) still work. Keep the state private and encrypted.
- Not verified: Secret Manager availability in `nl-ams` (dev). If the apply fails there, set `secrets_enabled = false` for dev.

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

1. The Private Network option of each offer. Run `./find-pn-options.sh <zone> <offer> [hourly|monthly]` (needs `SCW_SECRET_KEY`) and put the printed ID in `app_private_network_option_id` / `cartography_private_network_option_id`. See "Error: offer-compatible private network option" below.
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

## Error: offer-compatible private network option

```
Error: attaching a private network requires enabling an offer-compatible private network option
  with scaleway_baremetal_server.app[0]
```

What the provider checks (scaleway 2.93.0, `internal/services/baremetal/helpers.go`): the server has a `private_network` block, so at least one ID in its `options` blocks must be one of the options **listed by the API for that offer** with a `private_network` capability. If none matches, the plan fails with this error.

Two causes:

1. **The option name lookup picked another option.** `data "scaleway_baremetal_option"` searches by name across the whole zone and keeps the first match. Several options can carry the same name (for example one per offer range), so the ID it returns may not belong to your offer.
2. **The offer has no Private Network option at all**, or not under that name. Some entry-range offers cannot join a Private Network.

Fix:

```bash
cd infrastructure/terraform
export SCW_SECRET_KEY=...                      # same key as for Terraform
./find-pn-options.sh nl-ams-1 EM-A410X-SSD hourly
```

- If it prints an option, copy its ID into `envs/dev.tfvars`:
  ```hcl
  app_private_network_option_id = "<option_id printed by the script>"
  ```
  The ID takes priority over `app_private_network_option_name`. Run `./tf.sh dev plan` again.
- If it prints "NO Private Network option", that offer cannot be used in this design (the server must be in the Private Network behind the load balancer). Pick another offer and run the script again for it. In AMS, `EM-B212X-SSD` was offered with "Private Networks 1 Gbps feature" on the order screen.
- If it prints "No offer named ... in <zone>", the offer does not exist in that zone or with that subscription period (`offer_subscription_period`).

Do the same for the cartography server with `cartography_private_network_option_id`.
