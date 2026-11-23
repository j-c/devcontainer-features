#!/usr/bin/env bash
# Integration test with the REAL Claude Code CLI: forces an OAuth token refresh
# against a local fake token endpoint (mitmproxy) and checks, via strace, how the
# CLI saves .credentials.json and ~/.claude.json inside a container built with
# this feature. DUMMY tokens only.
#
# Requires on the host: docker, devcontainer CLI, mitmdump (mitmproxy), and a
# Linux x64 Claude Code binary:  CLAUDE_BIN=/path/to/claude ./real-cli-refresh.sh
# The container needs strace: it is apt-installed, or set CCC_TEST_IMAGE to a
# base image that already has it.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
: "${CLAUDE_BIN:?set CLAUDE_BIN to a Linux claude binary}"
command -v mitmdump >/dev/null || { echo "mitmdump not found"; exit 2; }
WORK="$(mktemp -d)"; WS="$WORK/ccc-cli-ws"; PORT="${PORT:-18080}"
cleanup() { [ -n "${MPID:-}" ] && kill "$MPID" 2>/dev/null; [ -n "${KEEP:-}" ] && { echo "kept $WORK"; return; }; rm_ws_containers "$WS"; docker volume rm -f ccc-cli-ws-claude-code-config >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT

FAKE_OAUTH_LOG="$WORK/oauth.log" mitmdump --listen-host 127.0.0.1 -p "$PORT" -s "$(dirname "$0")/fake_oauth.py" --set confdir="$WORK/mitm" >"$WORK/mitm.log" 2>&1 & MPID=$!
for _ in $(seq 30); do [ -f "$WORK/mitm/mitmproxy-ca-cert.pem" ] && break; sleep 0.5; done
make_ws "$WS" ', "runArgs": ["--network=host"]'
up "$WS" || exit 1
cid="$(docker ps -q --filter "label=devcontainer.local_folder=$WS")"
docker cp "$CLAUDE_BIN" "$cid:/usr/local/bin/claude" >/dev/null
docker cp "$WORK/mitm/mitmproxy-ca-cert.pem" "$cid:/tmp/mitm-ca.pem" >/dev/null
docker exec "$cid" sh -c 'command -v strace >/dev/null || (apt-get update -qq && apt-get install -y -qq strace) >/dev/null 2>&1'
V=/usr/local/share/claude-code-config
past=$(( ($(date +%s) - 3600) * 1000 ))
dexec "$WS" sh -c "umask 077; printf '{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-DUMMY-old\",\"refreshToken\":\"sk-ant-ort01-DUMMY-old\",\"expiresAt\":$past,\"scopes\":[\"user:inference\",\"user:profile\"],\"subscriptionType\":\"max\"}}' > $V/.credentials.json"
before="$(dexec "$WS" sha256sum $V/.credentials.json | cut -c1-64)"
dexec "$WS" sh -c "HTTPS_PROXY=http://127.0.0.1:$PORT NODE_EXTRA_CA_CERTS=/tmp/mitm-ca.pem DISABLE_AUTOUPDATER=1 \
  timeout 60 strace -f -qq -e trace=rename,renameat,renameat2,chmod,fchmodat -o /tmp/st.log claude -p hi >/dev/null 2>&1; true"
after="$(dexec "$WS" sha256sum $V/.credentials.json | cut -c1-64)"
expect "fake token endpoint was called"          grep -q 'oauth/token' "$WORK/oauth.log"
expect "CLI saved refreshed credentials"         test -n "$after" -a "$before" != "$after"
expect "save used rename into the volume, no EBUSY" dexec "$WS" sh -c "grep -q 'credentials.json\") = 0' /tmp/st.log && ! grep -q EBUSY /tmp/st.log"
expect "chmod 600 succeeded"                     dexec "$WS" sh -c "grep -q 'credentials.json\", 0600) = 0' /tmp/st.log && ! grep -q 'credentials.json.*EPERM' /tmp/st.log"
expect "credentials regular file vscode:600"     dexec "$WS" sh -c "[ -f $V/.credentials.json ] && [ ! -L $V/.credentials.json ] && [ \$(stat -c %U:%a $V/.credentials.json) = vscode:600 ]"
expect "~/.claude.json still a symlink after CLI writes" dexec "$WS" test -L /home/vscode/.claude.json
expect ".claude.json written in the volume"      dexec "$WS" sh -c "grep -q '$V/.claude.json\") = 0' /tmp/st.log"
expect "status helper OK"                        dexec "$WS" claude-code-config-status
finish
