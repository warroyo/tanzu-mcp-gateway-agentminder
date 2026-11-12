#!/usr/bin/env python3
"""Creates the AgentMinder side, through the tenant admin API:

  resource server  <prefix>-echo-mcp: an AI resource server in front of the
                   echo server. Two intents: echo.read unlocks whoami and
                   echo.write unlocks reset. Its AgentMinder gateway URL
                   becomes its primary audience.
  agent client     <prefix>-agent: a confidential client for the agent.
  policy           <prefix>-agent: grants the client both intents. The demo
                   revokes echo.write (scripts/demo.sh).
  AuthClientPolicy the client is added as a principal, which AgentMinder
                   needs before it issues the client tokens with intents.

Safe to rerun: it records what it made in .state/agentminder.json and skips
those. Writes the agent's credentials to .state/agent-client.json (0600).
Reads config.env. Standard library only.
"""
import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(ROOT, ".state")


def load_config():
    cfg = {}
    with open(os.path.join(ROOT, "config.env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k] = v.strip().strip('"')
    return cfg


CFG = load_config()
TENANT = CFG["AM_TENANT_URL"].rstrip("/")
PREFIX = CFG.get("AM_PREFIX") or "demo"
INSECURE = CFG.get("INSECURE") == "1"
ECHO_URL = f"https://{CFG['ECHO_APP']}.{CFG['APPS_DOMAIN']}/mcp"
INTENT = "urn:iam:agent:intent:"
# Intents are permissions; each unlocks one or more tools.
INTENTS = {"echo.read": ["whoami"], "echo.write": ["reset"]}
GRANTED = ["echo.read", "echo.write"]
TOOLS = [t for tools in INTENTS.values() for t in tools]
# Token lifetime. A token's intents are fixed when it is minted; the policy is checked on every call.
# Long enough to demo in the Inspector UI without pasting a token often.
TOKEN_SECONDS = "900"

if INSECURE:
    CTX = ssl._create_unverified_context()
else:
    CTX = ssl.create_default_context(cafile=CFG.get("CA_FILE") or None)

os.makedirs(STATE, mode=0o700, exist_ok=True)
IDS_FILE = os.path.join(STATE, "agentminder.json")
ids = json.load(open(IDS_FILE)) if os.path.exists(IDS_FILE) else {}


def save():
    with open(IDS_FILE, "w") as f:
        json.dump(ids, f, indent=1)


def write_secret(name, obj):
    fd = os.open(os.path.join(STATE, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, json.dumps(obj).encode())
    os.close(fd)


def admin_token():
    form = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "urn:iam:myscopes"}).encode()
    basic = base64.b64encode(f"{CFG['AM_ADMIN_CLIENT_ID']}:{CFG['AM_ADMIN_CLIENT_SECRET']}".encode()).decode()
    req = urllib.request.Request(f"{TENANT}/oauth2/v1/token", form, {"Authorization": f"Basic {basic}"})
    with urllib.request.urlopen(req, context=CTX) as r:
        return json.load(r)["access_token"]


TOKEN = admin_token()


def call(method, path, body=None):
    req = urllib.request.Request(
        TENANT + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, context=CTX) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read()[:400].decode(errors='replace')}")


def gateway_url(app_id):
    # AgentMinder's gateway route for a resource server: its app ID,
    # base64 without padding.
    return f"{TENANT}/aigateway/v1/mcp/" + base64.b64encode(app_id.encode()).decode().rstrip("=")


server_name = f"{PREFIX}-echo-mcp"
client_name = f"{PREFIX}-agent"

server = {
    "status": "active",
    "name": server_name,
    "description": "Echo MCP server behind the Tanzu MCP Gateway",
    "clientType": "CONFIDENTIAL",
    "allowedOpenIDScopes": ["openid", "profile", "email"],
    "allowedGrantTypes": ["client_credentials", "authorization_code", "urn:ietf:params:oauth:grant-type:jwt-bearer"],
    "allowedOperations": ["introspect"],
    "userInfoEndpointResponseFormat": "PLAIN_JSON",
    "isOidcApp": True,
    "isResourceServerApp": True,
    "isAiResourceServerApp": True,
    "requireAccessControl": "tenant",
    "redirectURIs": [f"{TENANT}/ui/v1/adminconsole/"],
    "mcpServerEndpoint": ECHO_URL,
    "secondaryAudiences": [ECHO_URL],
    "mcpIgnoreSslValidation": INSECURE,
    "mcpRequireAccessToken": True,
    "mcpDiscoverRequireAccessToken": True,
    "enforcePolicies": True,
    # A tool with no binding can't be called.
    "protectedByDefault": True,
    "resScope": f"urn:rs:{server_name}",
    "resourceServerScopes":
        [{"scope": t, "description": t, "label": t, "consentRequired": False, "isDefaultScope": True, "risk": "normal"}
         for t in TOOLS] +
        [{"scope": INTENT + i, "description": f"intent {i}", "label": i, "consentRequired": False, "isDefaultScope": False,
          "risk": "elevated" if i.endswith("write") else "normal"} for i in INTENTS],
    # Which intent unlocks each tool.
    "agentToolBindings": [{"toolName": t, "intentScope": INTENT + i, "skill": "", "description": t}
                          for i, tools in INTENTS.items() for t in tools],
}

# The gateway URL comes from the app ID, which exists only after the create.
# So: create with the echo URL as audience, then PUT the whole app with the
# gateway URL as the primary audience.
if "server" not in ids:
    r = call("POST", "/admin/v1/Apps", {**server, "primaryAudience": ECHO_URL})
    ids.update(server=r["appId"], server_client_id=r.get("clientId"))
    save()
ids["gateway_url"] = gateway_url(ids["server"])
save()
call("PUT", f"/admin/v1/Apps/{ids['server']}",
     {**server, "appId": ids["server"], "clientId": ids["server_client_id"], "primaryAudience": ids["gateway_url"]})

if "client" not in ids:
    r = call("POST", "/admin/v1/Apps", {
        "status": "active",
        "name": client_name,
        "description": "Agent client for the Tanzu MCP Gateway demo",
        "clientType": "CONFIDENTIAL",
        "requireAccessControl": "tenant",
        "allowedOpenIDScopes": ["openid", "email", "profile"],
        "redirectURIs": [f"{TENANT}/ui/v1/adminconsole/"],
        "allowedGrantTypes": ["client_credentials", "urn:ietf:params:oauth:grant-type:jwt-bearer"],
        "allowedOperations": ["introspect"],
        "skewTimeSecs": 0,
        "userInfoEndpointResponseFormat": "PLAIN_JSON",
        "itEncryptionTarget": "NONE",
        "metadata": [{"name": "urn:iam:app:oauthAccessTokenExpirySecs", "value": TOKEN_SECONDS}],
    })
    ids["client"] = r["appId"]
    save()
    write_secret("agent-client.json", {"client_id": r["clientId"], "client_secret": r["secret"]})

if "policy" not in ids:
    r = call("POST", "/admin/v1/AuthZPolicies", {
        "policyName": client_name,
        "displayName": client_name,
        "description": "Grants the demo agent read and write",
        "policySubType": "role",
        "status": "active",
        "matchAnyApp": False,
        "apps": [{"id": ids["server"], "name": server_name}],
        "rules": [{
            "conditions": {"principal": {"clientApp": {"operator": "in", "value": [ids["client"]]}}},
            "result": {"effect": "grant", "msg": client_name, "privileges": [INTENT + i for i in GRANTED]},
        }],
    })
    ids["policy"] = r["policyId"]
    save()

if "auth_client_policy" not in ids:
    pols = call("GET", "/admin/v1/AuthZPolicies?filter=" + urllib.parse.quote('policyName eq "AuthClientPolicy"'))
    if isinstance(pols, dict):
        pols = pols.get("Resources") or pols.get("resources") or pols.get("items") or []
    match = [p for p in pols if p.get("policyName") == "AuthClientPolicy"]
    if not match:
        sys.exit("AuthClientPolicy not found")
    pid = match[0]["policyId"]
    call("POST", "/admin/v1/AdminRolesDelegator",
         {"id": pid, "principal": {"clientApp": {"operator": "in", "value": [ids["client"]]}}})
    ids["auth_client_policy"] = pid
    save()

print(json.dumps(ids, indent=1))
print("The AgentMinder gateway route can take 30-60 seconds to start answering.", file=sys.stderr)
