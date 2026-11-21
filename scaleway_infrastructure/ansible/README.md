# Ansible: baseline and k3s on the Elastic Metal servers

Terraform creates the two Elastic Metal servers (`<env>-app`, `<env>-cartography`). This project configures them afterwards:

- baseline: packages, time, unattended upgrades, SSH hardening, fail2ban, host firewall
- optional Private Network VLAN interface (netplan), UNVERIFIED
- Docker Engine (official apt repository, pinned)
- k3s, single server, pinned version, on the app server only
- Argo CD (optional, off by default)
- cartography server layout (placeholder only)

Dev and prod are separate: each has its own inventory, variables and vault, selected by `run.sh <dev|prod>`. There are no shared environment values.

## Why Ansible and not cloud-init

Cloud-init runs once at first boot, cannot be re-run, reports errors poorly, and changing `cloud_init` on a paid Elastic Metal server may force a reinstall. It has no idempotence, no upgrades (k3s version bumps) and is a poor place for secrets. Ansible is re-runnable, idempotent, supports `--check`/`--diff`/tags and handles upgrades.

A tiny optional first-boot file is provided in [`cloud-init/minimal.yaml`](cloud-init/minimal.yaml) (admin user, SSH keys, python3). Ansible does not need it. Pass it with:

```bash
cd infrastructure/terraform
TF_VAR_app_cloud_init="$(cat ../ansible/cloud-init/minimal.yaml)" \
TF_VAR_cartography_cloud_init="$(cat ../ansible/cloud-init/minimal.yaml)" ./tf.sh dev plan -out tfplan-dev
```

(`.tfvars` files cannot call `file()`; in a `.tf` override you can write `file("${path.module}/../ansible/cloud-init/minimal.yaml")`.) Elastic Metal cloud-init support is NOT verified.

## Prerequisites

- Controller: Python 3.12 (used for validation), ansible-core 2.21.x, optionally ansible-lint and yamllint (pinned in `requirements.txt`).
- Collections (pinned in `requirements.yml`): `ansible.posix`, `community.general`, `community.docker`.
- Targets: Ubuntu with python3 and passwordless sudo for the SSH user (`ubuntu`, Terraform `server_ssh_user`).
- Terraform state of the environment (for `gen-inventory.sh`).

```bash
cd infrastructure/ansible
python3 -m venv .venv && . .venv/bin/activate      # .venv is a local choice, add it to your own ignore list
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p .ansible/collections
```

## Layout

```
ansible.cfg  requirements.yml  requirements.txt  run.sh  gen-inventory.sh
playbooks/    site, base, network, docker, k3s, argocd, cartography (+ guard.yml)
roles/        base, network, docker, k3s, argocd, cartography
inventories/<env>/hosts.yml.example                      -> hosts.yml            (git-ignored, generated)
inventories/<env>/group_vars/all/main.yml.example        -> main.yml             (git-ignored, your values)
inventories/<env>/group_vars/all/terraform.yml.example   -> terraform.yml        (git-ignored, generated)
inventories/<env>/group_vars/all/vault.yml.example       -> vault.yml            (git-ignored, encrypted)
cloud-init/minimal.yaml  fetched/ (kubeconfigs, git-ignored)
```

## End-to-end flow

1. Terraform: `./tf.sh <env> apply` with `create_app_server` and `create_cartography_server` set to `true`.
2. Inventory over public IPs for the first run: `./gen-inventory.sh <env> --mode public`. Then `cp inventories/<env>/group_vars/all/main.yml.example inventories/<env>/group_vars/all/main.yml` and set `admin_cidrs` (your IPs, like Terraform `bastion_allowed_cidrs`).
3. Secrets: copy `vault.yml.example` to `vault.yml`, set a real token (`openssl rand -hex 32`), then encrypt (see Vault).
4. First run over the public IP: `./run.sh <env> base`. The firewall allows SSH only from `admin_cidrs` and the Private Network. If your IP is not covered yet, set `base_firewall_relaxed: true` for this run only, then set it back to `false` and re-run.
5. Optional Private Network interface: set `network_configure: true`, run `./run.sh <env> network` (UNVERIFIED, see below).
6. Switch to the bastion: `./gen-inventory.sh <env> --mode bastion --force` (ProxyJump `bastion@<gateway_ip>:61000`, targets are the private IPs). This needs the private interface to work.
7. Everything: `./run.sh <env> site`.

The manual equivalent of ProxyJump: `ssh -J bastion@<gateway_ip>:61000 ubuntu@<private_ip>`.

`gen-inventory.sh` reads `./tf.sh <env> output -json` (real names: `gateway_public_ip`, `bastion_ssh_port`, `app_server_private_ip`, `cartography_server_private_ip`, `app_server_public_ipv4`, `backups_bucket_name`, plus the new `private_network_cidr`, `cartography_server_public_ipv4`, `app_server_private_vlan`, `cartography_server_private_vlan`). It never reads passwords or secret keys. Without `--force` it refuses to overwrite existing files.

## Dev and prod

```bash
./run.sh dev  site --check --diff      # dry run (only against a real, intended host)
./run.sh prod site
```

`run.sh` refuses any environment other than `dev` or `prod`, always passes `-e env_name=<env>` and the matching inventory, and the `guard` play stops the run if `env_name` and the inventory directory or host names disagree. Use a different vault password per environment: `.vault_pass.dev`, `.vault_pass.prod` (or one `.vault_pass`); if none exists and `vault.yml` is encrypted, you are prompted.

## Tags and single runs

Tags: `base`, `packages`, `ssh`, `firewall`, `network`, `docker`, `k3s`, `kubeconfig`, `argocd`, `cartography`.

```bash
./run.sh dev site --tags k3s --limit dev-app
./run.sh dev base --tags firewall
```

## Vault

```bash
cp inventories/dev/group_vars/all/vault.yml.example inventories/dev/group_vars/all/vault.yml
# edit vault_k3s_token, then
ansible-vault encrypt inventories/dev/group_vars/all/vault.yml --vault-password-file .vault_pass.dev
ansible-vault edit    inventories/dev/group_vars/all/vault.yml --vault-password-file .vault_pass.dev
```

`.vault_pass*` and the real `vault.yml` are git-ignored. The k3s role refuses a placeholder or a token shorter than 32 characters.

## k3s

- The role writes `/etc/rancher/k3s/config.yaml` (token, `tls-san` = 127.0.0.1, hostname, private IP; `node-ip` and `advertise-address` = private IP only when `network_configure` is true; `write-kubeconfig-mode: 0600`; secrets encryption), then runs the install script of the pinned tag. The bundled Traefik is kept. To bring your own ingress set `k3s_disable: [traefik]`; `servicelb` can be disabled the same way.
- Single node, embedded SQLite. Not on the cartography server.
- Upgrade: change `k3s_version` (exact, for example `v1.37.2+k3s1`; `latest` and channels are refused), run `./run.sh <env> k3s`. k3s restarts, so expect a short downtime. Snapshot or back up `/var/lib/rancher/k3s/server` first (not automated). Before prod, check `curl -s https://update.k3s.io/v1-release/channels`: the pinned release was the GitHub "latest" and the stable channel may lag.
- Kubeconfig: installed in `~/.kube/config` of the SSH user on the server, and (with `k3s_fetch_kubeconfig: true`) copied to `fetched/<env>/<host>.kubeconfig` (mode 0600, git-ignored). The API (6443) is never public. Use a tunnel:

```bash
ssh -N -L 6443:127.0.0.1:6443 -J bastion@<gateway_ip>:61000 ubuntu@<private_ip>
KUBECONFIG=fetched/dev/dev-app.kubeconfig kubectl get nodes
```

## Argo CD (optional)

Set `argocd_enabled: true` (and optionally `argocd_root_app_repo_url` plus `argocd_root_app_path` for a root Application), then `./run.sh <env> argocd`. The pinned manifest is applied server-side. The run prints how to read the initial admin password and how to reach the UI with `kubectl port-forward` plus `ssh -L 8080:127.0.0.1:8080`. No Ingress is created. Credentials for private Git repos are out of scope.

## Private Network interface (role network, UNVERIFIED)

Off by default (`network_configure: false`). Each server has one NIC; the Private Network is a VLAN on it. The role writes `/etc/netplan/60-private-network.yaml` with `<parent>.<vlan>`, DHCP (IPAM), `use-routes: false` and `use-dns: false`, so the public default route stays (apt, Docker and k3s downloads need no NAT). Only the VLAN is declared; the installer's public NIC file is untouched. Alternative (not implemented): drop the public default route and use the gateway masquerade, which makes the gateway a single point of failure for updates. The Scaleway documentation page could not be consulted while writing this, so the netplan details, the NIC name and the VLAN id source are unconfirmed. Check with `ip -br link` and the Scaleway console first; set `network_parent_interface` if detection is wrong.

## Security notes

- Bare-metal servers have a public IPv4 that cannot be removed. The host firewall (ufw) denies incoming by default; SSH is allowed from `admin_cidrs` and the Private Network; TCP 80/443 only from the Private Network (`base_lb_source_cidrs`), so the NLB/WAF cannot be bypassed through the public IP.
- Docker and k3s hostPort traffic is NATed before ufw INPUT rules. The base role adds a raw-table drop for 80/443 from non-allowed sources on the public interface, and the Docker role documents binding to private IPs. Untested on a real host.
- 6443 is never opened; a check fails the k3s run if a ufw rule mentions it.
- Lockout safety: SSH allow rules are added before ufw is enabled, ufw is not enabled without an SSH allow rule, SSH hardening is refused without an authorized key, `sshd -t` runs before reload, and on the first enable a transient systemd timer disables ufw after `base_firewall_rollback_seconds` unless the new connection works (then the timer is stopped).
- SSH: key only, no root login, `AllowTcpForwarding yes` (needed for `-L` and `-J`). fail2ban ignores the Private Network so the bastion is not banned.
- The k3s token only comes from the vault and its tasks use `no_log`. Fetched kubeconfigs are 0600 and git-ignored.

## To verify

- Private Network netplan details, DHCP behaviour, NIC name and VLAN id on Elastic Metal; the new Terraform outputs (`*_private_vlan`, `cartography_server_public_ipv4`, `private_network_cidr`) were never applied.
- Whether the L4 NLB preserves client IPs (affects the source rule for 80/443; adjust `base_lb_source_cidrs`).
- Cloud-init support on the Elastic Metal offers.
- Ubuntu 26.04 compatibility: Docker repo suite `resolute` (packages 5:29.x were listed, installation untested), k3s support, `ssh.socket` activation (the handler reloads `ssh`), ufw/iptables-nft with k3s.
- Docker GPG key fingerprint (not checked by the role).
- The rollback timer and the raw-table guard behaviour on a real host.
- Out of scope: the cartography service itself, backups of the local NVMe data to the S3 backups bucket (restic/rclone suggested), k3s snapshots, WAF.

## Hardening notes

- `k3s_install_script_checksum` is empty by default. For prod, pin it: `curl -sL <k3s_install_script_url> | sha256sum`, then set `"sha256:<hex>"` in the inventory variables.
- `./run.sh` refuses to run when `vault.yml` holds clear-text secrets. Encrypt it with `ansible-vault encrypt`.
- Setting `base_firewall_relaxed` back to `false` and re-running `base` deletes the "SSH from anywhere" ufw rule.
