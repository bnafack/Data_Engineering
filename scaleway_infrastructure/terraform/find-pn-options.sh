#!/usr/bin/env bash
# List the Private Network options that an Elastic Metal offer really supports,
# with their IDs, so you can set *_private_network_option_id in envs/<env>.tfvars.
#
#   ./find-pn-options.sh <zone> <offer-name> [hourly|monthly]
#
# Example:
#   ./find-pn-options.sh nl-ams-1 EM-A410X-SSD hourly
#
# Needs: curl, python3, and SCW_SECRET_KEY exported (read-only access to
# Elastic Metal is enough). The key is sent to api.scaleway.com only, never printed.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <zone> <offer-name> [hourly|monthly]" >&2
  exit 1
fi
zone="$1"
offer="$2"
period="${3:-}"

if [[ -z "${SCW_SECRET_KEY:-}" ]]; then
  echo "SCW_SECRET_KEY is not set. Export your Scaleway secret key first." >&2
  exit 1
fi

api="https://api.scaleway.com/baremetal/v1/zones/${zone}"

# Offers of the zone matching the name (one per subscription period).
offers_json="$(curl -sS -f -G -H "X-Auth-Token: ${SCW_SECRET_KEY}" \
  --data-urlencode "name=${offer}" --data-urlencode "page_size=100" \
  "${api}/offers")" || { echo "Request to the Elastic Metal API failed (zone '${zone}', key permissions?)." >&2; exit 1; }

OFFERS="$offers_json" OFFER="$offer" PERIOD="$period" ZONE="$zone" python3 - <<'PY'
import json, os, sys

offers = json.loads(os.environ["OFFERS"]).get("offers", [])
name, period, zone = os.environ["OFFER"], os.environ["PERIOD"], os.environ["ZONE"]
offers = [o for o in offers if o.get("name") == name]
if period:
    offers = [o for o in offers if o.get("subscription_period") == period]

if not offers:
    sys.exit(f"No offer named '{name}'{' (' + period + ')' if period else ''} in {zone}. "
             "Check the name and the zone: the offer may not exist there.")

found = False
for o in offers:
    print(f"\nOffer {o['name']}  ({o.get('subscription_period')})  offer_id={o['id']}  stock={o.get('stock')}")
    pn = [opt for opt in o.get("options", []) if opt.get("private_network")]
    if not pn:
        print("  -> NO Private Network option: this offer cannot join a Private Network.")
        continue
    for opt in pn:
        found = True
        bw = opt["private_network"].get("bandwidth_in_bps", 0) / 1e9
        print(f"  option_id = \"{opt['id']}\"   name = \"{opt['name']}\"   "
              f"{bw:g} Gbps   enabled={opt.get('enabled')}   manageable={opt.get('manageable')}")

if found:
    print("\nPut the ID in envs/<env>.tfvars, for example:")
    print('  app_private_network_option_id = "<option_id from above>"')
else:
    print("\nNone of these offers supports a Private Network. Pick another offer "
          "(or remove the private_network block for this server).")
    sys.exit(2)
PY
