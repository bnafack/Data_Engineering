# Ansible, the simple way: Private Network, Docker and firewall

Three short steps. They configure only:

1. the **Private Network** interface (the VLAN that gives the server its `172.16.x.x` address) and **Docker**: `./run.sh dev setup`
2. the **bastion** route, so you reach the server without its public IP
3. a **firewall** that closes the public IP, which you can configure: `./run.sh dev firewall`

No SSH hardening, k3s, vault or passwords. For those, use [`DEPLOYMENT.md`](DEPLOYMENT.md) later.

The examples use the dev values (server `dev-app`, VLAN `2124`). Yours may differ: the IPs are in `inventories/dev/hosts.yml`.

## Before you start

- Terraform created the server (`create_app_server = true`).
- Your SSH key is loaded: `ssh-add ~/.ssh/id_ed25519`

## Part 1. Private Network and Docker

### 1. Install Ansible (once)

```bash
cd infrastructure/ansible
python3.12 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p .ansible/collections
```

It must be Python 3.12: ansible-core does not run on Python 3.15. If `venv` fails: `sudo apt install python3.12-venv`. Each new terminal: `cd infrastructure/ansible && . .venv/bin/activate`.

### 2. Create the inventory, over the public IP

The server only gets its private address after step 4, so the first run goes to the public IP:

```bash
./gen-inventory.sh dev --mode public --force
cat inventories/dev/hosts.yml        # check: ansible_host, private_ip and private_vlan are there
```

### 3. Check the connection

```bash
ansible -i inventories/dev/hosts.yml servers -m ansible.builtin.ping      # expect "pong"
```

### 4. Run it

```bash
./run.sh dev setup
```

At the end, `PLAY RECAP` must show `failed=0` and `unreachable=0`. Re-running is safe. To run one part: `--tags network` or `--tags docker`.

### 5. Check the result

```bash
ssh ubuntu@<public_ip>
ip -br addr show vlan2124         # expect your private IP, e.g. 172.16.64.5/22
sudo docker run --rm hello-world
```

`docker` without `sudo` works after you log out and in again.

## Part 2. Switch to the bastion

The Private Network exists now, so Ansible and you can reach the server through the Public Gateway:

```bash
./gen-inventory.sh dev --mode bastion --force
ansible -i inventories/dev/hosts.yml servers -m ansible.builtin.ping      # expect "pong"
```

Add to `~/.ssh/config` (the three IPs are in `inventories/dev/hosts.yml`):

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

```bash
ssh dev-app
```

If SSH reports `REMOTE HOST IDENTIFICATION HAS CHANGED`, the server was recreated and reuses its private IP. Check the new fingerprint (`ssh ubuntu@<public_ip> 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'`), then run `ssh-keygen -R <private_ip>`.

**Do not continue until `ssh dev-app` works.** The firewall in part 3 closes the public IP, and this route is your way in.

## Part 3. Firewall

After part 1 you can still reach the server on its public IP. Elastic Metal servers always keep a public IPv4, so the only way to close it is a firewall on the server.

```bash
./run.sh dev firewall
```

With no settings, this does:

| Traffic | Result |
|---|---|
| SSH from the Private Network (through the bastion) | allowed |
| SSH from the public IP | blocked |
| Any other incoming port | blocked |
| Outgoing traffic | allowed (apt, Docker, AWS and so on) |

Test from a second terminal, keeping the first one open:

```bash
ssh dev-app                   # through the bastion: must work
ssh ubuntu@<public_ip>        # must now time out
```

### Lockout protection

- The run **refuses to start** if your current connection is the one it would block. If you are connected over the public IP, it stops with `This SSH session comes from <ip>, which firewall_ssh_from would block` and changes nothing. In that case do Part 2 first.
- The SSH rules are added before the firewall is switched on.
- On the first start, a timer switches the firewall off again after 120 seconds unless a new connection works. A failed run therefore heals itself.
- Last resort: Scaleway console, Elastic Metal, rescue mode, then `ufw disable`.

### Configure it

Add the settings you need to `inventories/dev/group_vars/all/main.yml`. All are optional:

```yaml
# Who may use SSH. Default: only the Private Network (= the bastion).
firewall_ssh_from:
  - 172.16.64.0/22            # the Private Network
  - 203.0.113.10/32           # add your own address to also allow SSH on the public IP

# Extra open ports. src defaults to the Private Network.
firewall_allow:
  - { port: 80,   src: 172.16.64.0/22, comment: load balancer }
  - { port: 443,  src: 172.16.64.0/22, comment: load balancer }
  - { port: 8080, src: 203.0.113.10/32, comment: test from home }
  - { port: "8000:8100", src: any, proto: udp }       # a range, open to everyone
```

Then run `./run.sh dev firewall` again.

| Setting | Meaning |
|---|---|
| `firewall_ssh_from` | CIDRs allowed to use SSH. Default: the Private Network. |
| `firewall_allow` | List of ports to open: `port` (number or `8000:8100`), `src` (CIDR or `any`, default the Private Network), `proto` (`tcp` or `udp`, default `tcp`), `comment`. |
| `firewall_enable` | `false` writes the rules but leaves the firewall off. Check them with `ssh dev-app 'sudo ufw show added'`. |
| `firewall_reset` | `true` deletes all existing rules first, so your list is the whole truth. This also removes rules added by other roles such as k3s. |
| `firewall_check_ssh_source` | `false` turns off the lockout check. Not recommended. |

A rule you remove from `firewall_allow` is **not** deleted automatically. Remove it with `ssh dev-app 'sudo ufw status numbered'` then `sudo ufw delete <number>`, or set `firewall_reset: true` once.

### Good to know

- **No load balancer in dev?** To test a web app through the server's public IP, open the port to your own address: `{ port: 80, src: <your-ip>/32 }`. With a load balancer, use the Private Network range, as in the example.
- **Docker ports skip the firewall.** A port published with `docker run -p 8080:80` is reachable from outside even when `ufw` says no. Publish on the private IP (`-p 172.16.64.5:8080:80`) or on `127.0.0.1`, never on all addresses.
- **After enabling it, check that containers still reach the internet:** `ssh dev-app 'sudo docker run --rm alpine ping -c 1 1.1.1.1'`. I could not test this combination on your server.
- **The full guide's `base` step does the same job** (and more). Use one or the other, not both.

## If something fails

| Message | Fix |
|---|---|
| `Missing inventories/dev/hosts.yml` | Run part 1, step 2. |
| `Host key verification failed` | The server was recreated: `ssh-keygen -R <ip>`, then retry. |
| `Permission denied (publickey)` | Load your key with `ssh-add ~/.ssh/id_ed25519`. |
| `UNREACHABLE` in part 1 | You are in bastion mode before the VLAN exists. Run part 1, step 2 again with `--mode public`. |
| `The VLAN id is missing` | The inventory has no `private_vlan`. Run step 2 again after `terraform apply`. |
| `Could not get lock /var/lib/dpkg/lock` | The server is still doing its first updates. Wait two minutes and retry. |
| `Could not find exactly one netplan ethernet` | On the server: `sudo cat /etc/netplan/*.yaml`. Add `network_parent_interface: "<name under ethernets>"` to `main.yml`. |
| `... did not get 172.16.64.5` | DHCP did not answer. Add `network_use_dhcp: false` and `network_static_address: "172.16.64.5/22"` to `main.yml`. |
| apt error for the Docker repository | Add `docker_apt_suite: noble` to `main.yml`. |
| `This SSH session comes from <ip>, which firewall_ssh_from would block` | You are connected over the public IP. Do Part 2 first, or add that address to `firewall_ssh_from`. |
| `firewall_ssh_from must list at least one CIDR` | `terraform.yml` is missing (it holds the Private Network range). Run `./gen-inventory.sh dev --mode bastion --force`. |
| Locked out | Scaleway console, rescue mode, `ufw disable`. |

## Next

k3s, SSH hardening, Argo CD and the rest: [`DEPLOYMENT.md`](DEPLOYMENT.md).
