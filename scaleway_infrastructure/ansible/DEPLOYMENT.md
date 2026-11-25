# Ansible deployment guide – server configuration

Run this after Terraform has created the Elastic Metal servers (see `../terraform/DEPLOYEMENT.md`).
Ansible configures, in this order:

1. `network`: the Private Network VLAN (netplan)
2. `base`: packages, updates, SSH hardening, fail2ban, host firewall
3. `docker`: Docker Engine
4. `k3s`: k3s on the app server only
5. `argocd`: Argo CD (optional, off by default)
6. `cartography`: base layout of the cartography server

Always run playbooks through `./run.sh <dev|prod> <playbook>`. It picks the right inventory, variables and vault, and refuses any other environment.

Examples below use the dev values:

| Item | Dev value | Terraform output |
|---|---|---|
| Bastion (Public Gateway) | `51.15.57.196:61000` | `gateway_public_ip`, `bastion_ssh_port` |
| App server, private | `172.16.64.5` | `app_server_private_ip` |
| App server, public | `51.158.200.240` | `app_server_public_ipv4` |
| VLAN id | `2116` | `app_server_private_vlan` |
| Private Network | `172.16.64.0/22` | `private_network_cidr` |
| Database, private | `172.16.64.2:5432` | `db_private_host`, `db_private_port` |

## 0. Prerequisites

- Terraform state of the environment (Ansible reads its outputs).
- Your SSH key is in Terraform `ssh_public_keys`, and your public IP is in `bastion_allowed_cidrs`.
- Python 3.12 on your laptop. ansible-core 2.21 does **not** run on Python 3.15.

```bash
cd infrastructure/ansible

# Python venv. If "ensurepip is not available": sudo apt install python3.12-venv
python3.12 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p .ansible/collections
ansible --version    # ansible [core 2.21.6]
```

Without sudo, create the venv with `python3.12 -m venv --without-pip .venv`, then install pip with `curl -sS https://bootstrap.pypa.io/get-pip.py | .venv/bin/python`.

## 1. Environment variables

```bash
cp inventories/dev/group_vars/all/main.yml.example inventories/dev/group_vars/all/main.yml
```

Edit `main.yml`:

```yaml
env_name: dev
timezone: Europe/Amsterdam

# SSH allowed from these CIDRs AND from the Private Network.
# Bastion-only (public-IP SSH blocked for everyone): use the Private Network itself.
admin_cidrs:
  - 172.16.64.0/22

base_firewall_relaxed: false

network_configure: true
network_parent_interface: ""     # auto-detects eth0; set "eth0" to force it

docker_enabled: true
k3s_version: "v1.37.2+k3s1"
k3s_fetch_kubeconfig: true
argocd_enabled: false
```

If you prefer to keep SSH on the public IP from your own address, list your IP instead (`- <your-ip>/32`).

## 2. Secrets (Ansible Vault)

```bash
cp inventories/dev/group_vars/all/vault.yml.example inventories/dev/group_vars/all/vault.yml
openssl rand -hex 32            # put the result in vault_k3s_token

openssl rand -base64 32 > .vault_pass.dev && chmod 600 .vault_pass.dev
ansible-vault encrypt inventories/dev/group_vars/all/vault.yml --vault-password-file .vault_pass.dev
```

Keep `.vault_pass.dev` safe and out of Git (it is git-ignored). Use a different password and token for prod. `run.sh` refuses to run if `vault.yml` is not encrypted.

## 3. Inventory from Terraform

Two modes:

| Mode | Ansible connects to | Use it when |
|---|---|---|
| `--mode public` | the public IP (`51.158.200.240`) | first run, before the VLAN exists |
| `--mode bastion` | the private IP (`172.16.64.5`) through `bastion@51.15.57.196:61000` | once the VLAN works (normal mode) |

Without a Public Gateway (`create_public_gateway = false` in Terraform) there is no bastion: only `--mode public` works (`--mode bastion` stops with "gateway_public_ip is null"). In that case list your admin IPs in `admin_cidrs` instead of the Private Network range, and without a load balancer add them to `base_lb_source_cidrs` to reach ports 80/443 on the server's public IP.

```bash
./gen-inventory.sh dev --mode public
```

It writes `inventories/dev/hosts.yml` and `inventories/dev/group_vars/all/terraform.yml` (both git-ignored). Regenerate instead of editing. Add `--force` to overwrite existing files.

Test the connection:

```bash
ansible -i inventories/dev/hosts.yml servers -m ansible.builtin.ping
```

## 4. Private Network (network role)

```bash
./run.sh dev network --check --diff
./run.sh dev network
```

The role writes `/etc/netplan/60-private-network.yaml`:

```yaml
network:
  version: 2
  vlans:
    vlan2116:
      id: 2116
      link: eth0
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
        use-dns: false
```

- `link:` is the **netplan ID** (`eth0`) from `/etc/netplan/50-cloud-init.yaml`, not the kernel name (`eno1`). The role finds it by MAC.
- The file is checked with `netplan generate` before `netplan apply`. If it is invalid, the previous file is restored.
- The role then checks that `vlan2116` has `172.16.64.5` and that the default route is still on `eno1`.

The dev app server was already configured by hand with the same file and path. The role takes it over; `--check --diff` should only show the header comment changing.

## 5. Switch to the bastion

```bash
./gen-inventory.sh dev --mode bastion --force
ansible -i inventories/dev/hosts.yml servers -m ansible.builtin.ping
```

From now on, every run goes through the bastion. Manual equivalent: `ssh -J bastion@51.15.57.196:61000 ubuntu@172.16.64.5`.

## 6. Base setup and firewall

```bash
./run.sh dev base --check --diff
./run.sh dev base
```

Result on the server (ufw):
- Incoming denied by default.
- SSH (22) only from `admin_cidrs` and the Private Network. With `admin_cidrs: [172.16.64.0/22]`, the public IP no longer accepts SSH.
- 80/443 only from the Private Network (load balancer traffic).
- 6443 (k3s API) never opened.

Lockout safety: the SSH rules are added before ufw is enabled, and on the first enable a timer turns ufw off again unless the new connection works. Keep a session open while testing:

```bash
ssh dev-app                     # through the bastion: must still work
ssh ubuntu@51.158.200.240       # public IP: must now time out
```

If you are locked out: Scaleway console → Elastic Metal → rescue mode, then `ufw disable`.

## 7. Docker, k3s, cartography

Everything at once:

```bash
./run.sh dev site --check --diff
./run.sh dev site
```

Or one part at a time:

```bash
./run.sh dev docker
./run.sh dev k3s
./run.sh dev cartography
./run.sh dev argocd          # only with argocd_enabled: true
```

Single tags: `--tags k3s`, `--tags firewall`, and so on. Limit to one host: `--limit dev-app`.

## 8. Check the result

```bash
# Server
ssh dev-app 'ip -br addr show vlan2116; sudo ufw status; sudo k3s kubectl get nodes'

# k3s API through a tunnel (6443 is never public)
ssh -N -L 6443:127.0.0.1:6443 dev-app &
KUBECONFIG=fetched/dev/dev-app.kubeconfig kubectl get nodes

# Database from the server, over the Private Network
ssh dev-app 'nc -zv 172.16.64.2 5432'

# Load balancer: backend healthy once something listens on 80/443 (Traefik in k3s)
curl -I http://51.15.63.209
```

`~/.ssh/config` used above:

```
Host dev-bastion
  HostName 51.15.57.196
  Port 61000
  User bastion
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host dev-app
  HostName 172.16.64.5
  User ubuntu
  ProxyJump dev-bastion
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host dev-db
  HostName 51.15.57.196
  Port 61000
  User bastion
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  LocalForward 127.0.0.1:15432 172.16.64.2:5432
  ExitOnForwardFailure yes
```

## 9. Later changes

| Change | Command |
|---|---|
| Upgrade k3s | edit `k3s_version`, then `./run.sh dev k3s` (short downtime, back up `/var/lib/rancher/k3s/server` first) |
| New admin IP | edit `admin_cidrs`, then `./run.sh dev base --tags firewall` |
| Server recreated by Terraform | `./gen-inventory.sh dev --mode public --force`, then restart from step 4 |
| Edit secrets | `ansible-vault edit inventories/dev/group_vars/all/vault.yml --vault-password-file .vault_pass.dev` |

## 10. Prod

Same steps with `prod`: `inventories/prod/...`, `.vault_pass.prod`, `./gen-inventory.sh prod ...`, `./run.sh prod ...`. Use its own vault password, its own k3s token and the prod Private Network CIDR (`172.16.68.0/22` by default) in `admin_cidrs`. In prod, also set `k3s_install_script_checksum` (see README "Hardening notes").

## Troubleshooting

| Error | Fix |
|---|---|
| `AttributeError: module 'dataclasses' has no attribute '_is_type'` | Wrong Python (3.15). Use the Python 3.12 venv from step 0 |
| `Missing inventories/dev/hosts.yml` | Run `./gen-inventory.sh dev --mode public` (or `bastion`) |
| `Refusing to run: ... clear text` | Encrypt `vault.yml` (step 2) |
| `UNREACHABLE` in bastion mode | The VLAN is not up yet: use `--mode public` and run `network` first |
| `interface 'eno1' is not defined` | Old role version, or `network_parent_interface: eno1`. Use `eth0` or leave it empty |
| `Could not find exactly one netplan ethernet` | Check `sudo cat /etc/netplan/*.yaml` and set `network_parent_interface` to the key under `ethernets:` |
| `... did not get 172.16.64.5` | DHCP did not answer: set `network_use_dhcp: false` and `network_static_address: "172.16.64.5/22"` |
| `Set private_network_cidr ... and a non-empty admin_cidrs` | `admin_cidrs` is empty: set it (step 1) and regenerate `terraform.yml` |
| Locked out after `base` | Rescue mode in the Scaleway console, `ufw disable` |
