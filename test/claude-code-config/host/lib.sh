#!/usr/bin/env bash
# Helpers for host-side claude-code-config tests (need docker + devcontainer CLI).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
nok() { echo "  FAIL: $1"; fail=$((fail+1)); }
expect() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else nok "$d"; fi; }
finish() { echo "== $pass passed, $fail failed"; [ "$fail" = 0 ]; }

# make_ws <dir> [extra-json-fields]: workspace using the local feature source
make_ws() {
    mkdir -p "$1/.devcontainer"
    rm -rf "$1/.devcontainer/claude-code-config"
    cp -r "$REPO/src/claude-code-config" "$1/.devcontainer/"
    cat > "$1/.devcontainer/devcontainer.json" <<JSON
{ "image": "${CCC_TEST_IMAGE:-mcr.microsoft.com/devcontainers/base:bookworm}", "remoteUser": "vscode",
  "features": { "./claude-code-config": {} } ${2:-} }
JSON
}
up()   { devcontainer up --workspace-folder "$1" "${@:2}" >"$1.up.log" 2>&1 || { echo "devcontainer up failed:"; tail -5 "$1.up.log"; return 1; }; }
dexec() { local ws="$1"; shift; devcontainer exec --workspace-folder "$ws" "$@" 2>/dev/null; }
rm_ws_containers() { docker ps -aq --filter "label=devcontainer.local_folder=$1" | xargs -r docker rm -f >/dev/null; }
