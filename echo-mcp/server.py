"""A tiny MCP server for testing the path through the gateways.

It speaks just enough of MCP over streamable HTTP (initialize, tools/list,
tools/call) and answers every tool call with what it received: the request
header names and a summary of the bearer token. The summary has the token's
SHA-256 prefix and its decoded claims, never the token itself.

It does not validate the token. A real MCP server behind AgentMinder must
check the issuer, that the audience includes the AgentMinder gateway URL,
and the signature. See docs/faq.md.

Standard library only. Listens on $PORT.
"""
import base64
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# whoami stands for a read tool and reset for a write tool. Both only echo.
TOOLS = {
    "whoami": "Read: show what the server received",
    "reset": "Write: pretend to reset something, and show what the server received",
}
AM_ISSUER = os.environ.get("AM_ISSUER", "")


def claims(token):
    try:
        part = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
    except Exception:
        return None


def auth_summary(headers):
    value = headers.get("Authorization")
    if not value:
        return {"present": False}
    scheme, _, token = value.partition(" ")
    return {
        "present": True,
        "scheme": scheme,
        "sha256": hashlib.sha256(token.encode()).hexdigest()[:12],
        "claims": claims(token),
    }


class Handler(BaseHTTPRequestHandler):
    def record(self, extra):
        rec = {
            "method": self.command,
            "path": self.path,
            "headers": sorted(self.headers.keys()),
            "auth": auth_summary(self.headers),
            **extra,
        }
        print(json.dumps(rec), flush=True)
        return rec

    def reply(self, code, body):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.record({})
        if self.path.startswith("/.well-known/oauth-protected-resource"):
            host = self.headers.get("Host", "")
            return self.reply(200, {"resource": f"https://{host}/mcp", "authorization_servers": [AM_ISSUER]})
        if self.path == "/health":
            return self.reply(200, {"ok": True})
        self.reply(404, {"error": "not found"})

    def do_DELETE(self):
        self.record({})
        self.reply(200, {})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            msg = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            msg = {}
        rec = self.record({"rpc": msg.get("method")})
        if "id" not in msg:  # a notification
            return self.reply(202, None)

        method, rid = msg.get("method"), msg["id"]
        if method == "initialize":
            result = {
                "protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "echo-mcp", "version": "0.1"},
            }
        elif method == "tools/list":
            result = {"tools": [
                {"name": t, "description": d, "inputSchema": {"type": "object", "properties": {}}}
                for t, d in TOOLS.items()
            ]}
        elif method == "tools/call":
            text = json.dumps({"tool": msg.get("params", {}).get("name"),
                               "headers": rec["headers"], "auth": rec["auth"]})
            result = {"content": [{"type": "text", "text": text}]}
        else:
            return self.reply(200, {"jsonrpc": "2.0", "id": rid,
                                    "error": {"code": -32601, "message": f"unknown method {method}"}})
        self.reply(200, {"jsonrpc": "2.0", "id": rid, "result": result})

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
