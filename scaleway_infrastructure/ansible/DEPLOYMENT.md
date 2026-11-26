# Ansible: full server setup

Run this after Terraform has created the server (`../terraform/DEPLOYEMENT.md`). It configures the app server in this order:

| Step | Command | What it does |
|---|---|---|
| 2 | `./run.sh dev setup` | Private Network interface and Docker |
| 4 | `./run.sh dev base` | updates, SSH hardening, fail2ban, firewall |
| 5 | `./run.sh dev k3s` | k3s (Kubernetes) on the app server |
| 6 | `./run.sh dev argocd` | Argo CD (optional) |

Only need the Private Network and Docker? Stop after step 2, or use [`SIMPLE.md`](SIMPLE.md).

Always run playbooks through `./run.sh <dev|prod> <playbook>`. It picks the right inventory and vault, and refuses any other environment. Every command below runs from `infrastructure/ansible`.

## 0. Before you start

```bash
python3.12 -m venv .venv && . .venv/bin/activate     # Python 3.12: ansible-core does not run on 3.15
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p .ansible/collections
ssh-add ~/.ssh/id_ed25519                             # your key, the one in Terraform ssh_public_keys
```

If `venv` fails: `sudo apt install python3.12-venv`. In each new terminal: `. .venv/bin/activate`.

## 1. Variables

```bash
cp inventories/dev/group_vars/all/main.yml.example inventories/dev/group_vars/all/main.yml
```

Set these in `main.yml`:

| Variable | Value |
|---|---|
| `admin_cidrs` | `["172.16.64.0/22"]` = SSH only through the bastion (the Private Network range). To also allow SSH from your own address, add `<your-ip>/32`. |
| `network_configure` | `true` (k3s uses the private IP too) |
| `k3s_version` | an exact version, for example `"v1.37.2+k3s1"` |
| `k3s_fetch_kubeconfig` | `true` to get a kubeconfig on your laptop |
| `argocd_enabled` | `false` unless you want Argo CD |

## 2. Network and Docker (over the public IP)

The server has no private address until its VLAN is configured, so the first run goes to the public IP:

```bash
./gen-inventory.sh dev --mode public --force
ansible -i inventories/dev/hosts.yml servers -m ansible.builtin.ping     # expect "pong"
./run.sh dev setup
```

Check on the server (`ssh ubuntu@<public_ip>`):

```bash
ip -br addr show | grep vlan        # your private IP, e.g. 172.16.64.5/22
sudo docker run --rm hello-world
```

## 3. Switch to the bastion

```bash
./gen-inventory.sh dev --mode bastion --force
ansible -i inventories/dev/hosts.yml servers -m ansible.builtin.ping     # expect "pong"
```

From now on Ansible reaches the server through the Public Gateway. For your own SSH, add to `~/.ssh/config`:

```
Host dev-bastion
  HostName <gateway_ip>
  Port 61000
  User bastion
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host dev-app
  HostName <private_ip>
  User ubuntu
  ProxyJump dev-bastion
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

The three IPs are in `inventories/dev/hosts.yml`. If SSH reports `REMOTE HOST IDENTIFICATION HAS CHANGED`, the server was recreated: confirm the fingerprint, then `ssh-keygen -R <private_ip>`.

## 4. Firewall and SSH hardening

Do this only once step 3 works. Once it runs with `admin_cidrs: ["172.16.64.0/22"]`, the public IP no longer accepts SSH.

```bash
./run.sh dev base
```

Result: incoming traffic denied by default. SSH (22) only from `admin_cidrs` and the Private Network. Ports 80 and 443 only from the Private Network (the load balancer). The k3s API port 6443 is never opened. SSH keeps key-only login and fail2ban is on.

Test from a second terminal, keeping the first one open:

```bash
ssh dev-app                       # through the bastion: must work
ssh ubuntu@<public_ip>            # must now time out
```

Safety: the SSH rules are added before the firewall is enabled, and a timer turns it off again if the new connection fails. If you are locked out anyway: Scaleway console, Elastic Metal, rescue mode, then `ufw disable`.

Without a load balancer (dev), test a web app through the server's public IP by adding your address to `base_lb_source_cidrs` in `main.yml`.

## 5. k3s

k3s needs a secret token, kept in an encrypted Ansible Vault file:

```bash
cp inventories/dev/group_vars/all/vault.yml.example inventories/dev/group_vars/all/vault.yml
#   set vault_k3s_token to the output of: openssl rand -hex 32
openssl rand -base64 32 > .vault_pass.dev && chmod 600 .vault_pass.dev
ansible-vault encrypt inventories/dev/group_vars/all/vault.yml --vault-password-file .vault_pass.dev
```

Keep `.vault_pass.dev` out of Git (it already is). `run.sh` uses it automatically. For plain `ansible ...` commands, add `--vault-password-file .vault_pass.dev`.

```bash
./run.sh dev k3s
```

Check:

```bash
ssh dev-app 'sudo k3s kubectl get nodes'                       # Ready

ssh -N -L 6443:127.0.0.1:6443 dev-app &                        # k3s API, never public: use a tunnel
KUBECONFIG=fetched/dev/dev-app.kubeconfig kubectl get nodes    # with k3s_fetch_kubeconfig: true
```

## 6. Optional: Argo CD and the cartography server

- **Argo CD:** set `argocd_enabled: true` (and `argocd_root_app_repo_url` for a root application), then `./run.sh dev argocd`. It prints how to open the UI through a tunnel.
- **Cartography server:** when it exists, `./gen-inventory.sh dev --mode bastion --force` adds it to the inventory. `./run.sh dev site` then configures it with the network, firewall and Docker. The cartography service itself is a placeholder.

## 7. Later

| Change | Command |
|---|---|
| Apply everything again | `./run.sh dev site` (safe to repeat) |
| Upgrade k3s | edit `k3s_version`, then `./run.sh dev k3s` (short downtime) |
| New admin IP | edit `admin_cidrs`, then `./run.sh dev base --tags firewall` |
| Server recreated by Terraform | `./gen-inventory.sh dev --mode public --force`, then restart from step 2 |
| Edit the secret | `ansible-vault edit inventories/dev/group_vars/all/vault.yml --vault-password-file .vault_pass.dev` |
| One part only | add `--tags network`, `--tags docker`, `--tags firewall`, or `--limit dev-app` |

**Prod:** the same steps with `prod` (`inventories/prod/...`, `.vault_pass.prod`, `./run.sh prod ...`). Use its own vault password, its own k3s token, and the prod Private Network range (`172.16.68.0/22` by default) in `admin_cidrs`. Also set `k3s_install_script_checksum` (see the README, "Hardening notes").

## Troubleshooting

| Error | Fix |
|---|---|
| `AttributeError: ... 'dataclasses' ... '_is_type'` | Wrong Python. Use the Python 3.12 venv (step 0). |
| `Missing inventories/dev/hosts.yml` | Run `./gen-inventory.sh dev --mode public --force`. |
| `UNREACHABLE` in bastion mode | The VLAN isn't up yet. Go back to step 2 (public mode, then `setup`). |
| `Permission denied (publickey)` | Load your key: `ssh-add ~/.ssh/id_ed25519`. |
| `Attempting to decrypt but no vault secrets found` | Add `--vault-password-file .vault_pass.dev` to the plain `ansible` command, or use `./run.sh`. |
| `Refusing to run: ... clear text` | Encrypt `vault.yml` (step 5). |
| `vault_k3s_token must be a real secret` | Put a real value in `vault.yml`, at least 32 characters. |
| `Set private_network_cidr ... and a non-empty admin_cidrs` | `admin_cidrs` is empty, or `terraform.yml` is missing: set it (step 1) and run `./gen-inventory.sh`. |
| Locked out after `base` | Rescue mode in the Scaleway console, then `ufw disable`. |
| Network or Docker errors in step 2 | See the table in [`SIMPLE.md`](SIMPLE.md). |
