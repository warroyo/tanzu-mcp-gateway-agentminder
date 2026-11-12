#!/usr/bin/env bash
# Deletes everything the other scripts made: the gateway, the echo app, and
# the AgentMinder objects listed in .state/agentminder.json.
. "$(dirname "$0")/lib.sh"
need python3
need cf

cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null
if cf service "$GATEWAY_NAME" >/dev/null 2>&1; then
  # If the broker can't deprovision, `cf purge-service-instance` removes the
  # record, and the gateway app in the system org has to go by hand.
  cf delete-service "$GATEWAY_NAME" -f --wait || echo "delete failed: see docs/faq.md" >&2
fi
cf delete "$ECHO_APP" -r -f

python3 - "$ROOT" <<'EOF'
import base64, json, os, ssl, sys, urllib.parse, urllib.request
root = sys.argv[1]
state = os.path.join(root, ".state", "agentminder.json")
if not os.path.exists(state):
    sys.exit(0)
cfg = dict(l.strip().split("=", 1) for l in open(os.path.join(root, "config.env"))
           if "=" in l and not l.lstrip().startswith("#"))
tenant = cfg["AM_TENANT_URL"].rstrip("/")
ctx = ssl._create_unverified_context() if cfg.get("INSECURE") == "1" else ssl.create_default_context(cafile=cfg.get("CA_FILE") or None)
basic = base64.b64encode(f"{cfg['AM_ADMIN_CLIENT_ID']}:{cfg['AM_ADMIN_CLIENT_SECRET']}".encode()).decode()
form = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "urn:iam:myscopes"}).encode()
with urllib.request.urlopen(urllib.request.Request(f"{tenant}/oauth2/v1/token", form, {"Authorization": f"Basic {basic}"}), context=ctx) as r:
    token = json.load(r)["access_token"]
ids = json.load(open(state))

def call(method, path, body=None):
    req = urllib.request.Request(tenant + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, context=ctx).read()
        print("deleted", path)
    except urllib.error.HTTPError as e:
        print("failed", method, path, e.code, e.read()[:200].decode(errors="replace"))

if ids.get("auth_client_policy") and ids.get("client"):
    call("DELETE", "/admin/v1/AdminRolesDelegator",
         {"id": ids["auth_client_policy"], "principal": {"clientApp": {"operator": "in", "value": [ids["client"]]}}})
if ids.get("policy"):
    call("DELETE", f"/admin/v1/AuthZPolicies/{ids['policy']}")
for key in ("client", "server"):
    if ids.get(key):
        call("DELETE", f"/admin/v1/Apps/{ids[key]}?force=true")
EOF

rm -rf "$STATE"
