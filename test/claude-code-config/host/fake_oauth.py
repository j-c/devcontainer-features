# mitmproxy addon: fakes the Claude OAuth token endpoint with DUMMY tokens so a
# real Claude Code CLI performs (and saves) a token refresh without real secrets.
# Every other request is answered locally; nothing leaves the machine.
import json, os, time
from mitmproxy import http
def request(flow: http.HTTPFlow):
    h = flow.request.pretty_host
    p = flow.request.path
    with open(os.environ.get("FAKE_OAUTH_LOG", "/tmp/fake-oauth.log"), "a") as f:
        f.write(f"{flow.request.method} {h}{p.split('?')[0]}\n")
    if h == "platform.claude.com" and p.startswith("/v1/oauth/token"):
        body = {"access_token": "sk-ant-oat01-DUMMY-" + str(int(time.time())),
                "refresh_token": "sk-ant-ort01-DUMMY-" + str(int(time.time())),
                "expires_in": 28800, "token_type": "Bearer",
                "scope": "user:inference user:profile user:sessions:claude_code",
                "account": {"uuid": "00000000-0000-0000-0000-000000000001", "email_address": "dummy@example.invalid"},
                "organization": {"uuid": "00000000-0000-0000-0000-000000000002", "name": "dummy"}}
        flow.response = http.Response.make(200, json.dumps(body), {"content-type": "application/json"})
    elif h.endswith("anthropic.com") or h.endswith("claude.com") or h.endswith("claude.ai"):
        flow.response = http.Response.make(401, json.dumps({"type":"error","error":{"type":"authentication_error","message":"dummy"}}), {"content-type":"application/json"})
    else:
        flow.response = http.Response.make(503, "blocked by lab", {})
