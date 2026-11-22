#!/usr/bin/env bash
# Legacy-volume migration and persistence across rebuilds.
# Uses DUMMY credentials only; never touches the real host ~/.claude.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
WORK="$(mktemp -d)"; WS="$WORK/ccc-reuse-ws"; VOL="ccc-reuse-ws-claude-code-config"
cleanup() { rm_ws_containers "$WS"; docker volume rm -f "$VOL" >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT
make_ws "$WS"
V=/usr/local/share/claude-code-config

echo "## 1. existing v1.0.0-style volume (root-owned, empty mount placeholders)"
docker volume rm -f "$VOL" >/dev/null 2>&1; docker volume create "$VOL" >/dev/null
docker run --rm -v "$VOL:/v" debian:bookworm-slim sh -c '
  : > /v/.credentials.json; : > /v/settings.json
  mkdir -p /v/projects; echo "{}" > /v/projects/old.jsonl
  printf "{\"hasCompletedOnboarding\":false,\"marker\":\"legacy\"}" > /v/.claude.json
  chown -R 0:0 /v; chmod 755 /v; chmod 644 /v/.claude.json'
up "$WS" || exit 1
expect "empty .credentials.json placeholder removed" dexec "$WS" test ! -e $V/.credentials.json
expect "empty settings.json placeholder removed"     dexec "$WS" test ! -e $V/settings.json
expect "volume re-owned by vscode, 700"              dexec "$WS" sh -c "[ \$(stat -c %U:%a $V) = vscode:700 ]"
expect "old files re-owned by vscode"                dexec "$WS" sh -c "[ -z \"\$(find $V ! -user vscode)\" ]"
expect "existing .claude.json kept (marker)"         dexec "$WS" jq -e '.marker == "legacy"' $V/.claude.json
expect "hasCompletedOnboarding false -> true"        dexec "$WS" jq -e '.hasCompletedOnboarding == true' $V/.claude.json
expect ".claude.json tightened to 600"               dexec "$WS" sh -c "[ \$(stat -c %a $V/.claude.json) = 600 ]"

echo "## 2. simulated login in container, then rebuild without cache"
dexec "$WS" sh -c "umask 077; printf '{\"claudeAiOauth\":{\"accessToken\":\"DUMMY-REUSE\"}}' > $V/.credentials.json.tmp && mv -f $V/.credentials.json.tmp $V/.credentials.json && chmod 600 $V/.credentials.json"
before="$(dexec "$WS" sha256sum $V/.credentials.json | cut -c1-64)"
rm_ws_containers "$WS"
up "$WS" --build-no-cache --remove-existing-container || exit 1
after="$(dexec "$WS" sha256sum $V/.credentials.json | cut -c1-64)"
expect "credentials survive rebuild (same hash)"     test -n "$before" -a "$before" = "$after"
expect "credentials still vscode:600 regular file"   dexec "$WS" sh -c "[ -f $V/.credentials.json ] && [ ! -L $V/.credentials.json ] && [ \$(stat -c %U:%a $V/.credentials.json) = vscode:600 ]"
expect "project history survives rebuild"           dexec "$WS" test -f $V/projects/old.jsonl
expect "status helper OK after rebuild"              dexec "$WS" claude-code-config-status

echo "## 3. restart (docker restart) is idempotent"
cid="$(docker ps -q --filter "label=devcontainer.local_folder=$WS")"
docker restart "$cid" >/dev/null
expect "credentials unchanged after restart"         test "$(dexec "$WS" sha256sum $V/.credentials.json | cut -c1-64)" = "$before"
expect "no moved-aside files"                        dexec "$WS" sh -c '! ls -A ~ | grep -q pre-claude-code-config'

echo "## 4. v1-source-style volume (dangling symlink into the old host mount)"
rm_ws_containers "$WS"; docker volume rm -f "$VOL" >/dev/null; docker volume create "$VOL" >/dev/null
docker run --rm -v "$VOL:/v" debian:bookworm-slim sh -c 'ln -s /usr/local/share/claude-code-host-claude/.credentials.json /v/.credentials.json; chown -h 1000:1000 /v/.credentials.json; chown 1000:1000 /v'
up "$WS" || exit 1
expect "dangling credentials symlink removed"        dexec "$WS" sh -c "[ ! -L $V/.credentials.json ] && [ ! -e $V/.credentials.json ]"
expect "status helper OK"                            dexec "$WS" claude-code-config-status

echo "## 5. a real ~/.claude.json created in the container (e.g. by a tool) is adopted, not lost"
rm_ws_containers "$WS"; docker volume rm -f "$VOL" >/dev/null
up "$WS" || exit 1
dexec "$WS" sh -c "rm $V/.claude.json ~/.claude.json && printf '{\"marker\":\"home\"}' > ~/.claude.json"
cid="$(docker ps -q --filter "label=devcontainer.local_folder=$WS")"; docker restart "$cid" >/dev/null
expect "home .claude.json adopted into the volume"   dexec "$WS" jq -e '.marker == "home" and .hasCompletedOnboarding == true' $V/.claude.json
expect "~/.claude.json is a symlink again"           dexec "$WS" test -L /home/vscode/.claude.json
finish
