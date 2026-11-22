#!/usr/bin/env bash
# Shared assertions for claude-code-config tests. Sourced by test.sh and the
# scenario scripts, which run inside the container as the remote user.
# Uses DUMMY credentials only.

CONFIG_DIR="/usr/local/share/claude-code-config"
ME="$(id -un)"

is_mountpoint() { awk -v p="$1" '$5 == p { f=1 } END { exit !f }' /proc/self/mountinfo; }
mounts_inside() { awk -v p="$CONFIG_DIR/" 'index($5, p) == 1' /proc/self/mountinfo | wc -l; }

# Replays the CLI's credential save (create temp, rename over target, chmod 600),
# as observed with strace on Claude Code 2.1.x.
simulate_cli_save() {
    local target="$CONFIG_DIR/.credentials.json" tmp="$CONFIG_DIR/.credentials.json.tmp.test$$"
    ( umask 077; printf '{"claudeAiOauth":{"accessToken":"DUMMY","refreshToken":"DUMMY","expiresAt":1}}' > "$tmp" ) || return 1
    mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
    chmod 600 "$target"
}

maybe_root() { # run as root if we can, for re-running the entrypoint
    if [ "$(id -u)" = 0 ]; then "$@"; elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then sudo -n "$@"; else return 2; fi
}

common_checks() {
    check "config volume is mounted" is_mountpoint "$CONFIG_DIR"
    check "nothing is mounted inside the config volume" test "$(mounts_inside)" = 0
    check "no host ~/.claude bind mount" bash -c '! grep -q "claude-code-host-claude\|/\.claude[ /]" /proc/self/mountinfo'
    check "CLAUDE_CONFIG_DIR is not set" test -z "${CLAUDE_CONFIG_DIR:-}"
    check "~/.claude -> volume" test "$(readlink "$HOME/.claude")" = "$CONFIG_DIR"
    check "~/.claude.json -> volume/.claude.json" test "$(readlink "$HOME/.claude.json")" = "$CONFIG_DIR/.claude.json"
    check "volume owned by $ME" test "$(stat -c %U "$CONFIG_DIR")" = "$ME"
    check "volume mode 700" test "$(stat -c %a "$CONFIG_DIR")" = 700
    check "everything in volume owned by $ME" test -z "$(find "$CONFIG_DIR" -xdev ! -user "$ME" -print -quit)"
    check "no v1 start script" test ! -e /usr/local/bin/claude-code-config-start.sh
    check "CLI-style credential save works" simulate_cli_save
    check "credentials are a regular file" bash -c "[ -f $CONFIG_DIR/.credentials.json ] && [ ! -L $CONFIG_DIR/.credentials.json ]"
    check "credentials mode 600" test "$(stat -c %a "$CONFIG_DIR/.credentials.json")" = 600
    check "credentials owned by $ME" test "$(stat -c %U "$CONFIG_DIR/.credentials.json")" = "$ME"
    check "status helper reports OK" bash -c 'claude-code-config-status >/tmp/ccc-status.log 2>&1'
}

onboarding_seeded_checks() {
    check ".claude.json exists" test -f "$CONFIG_DIR/.claude.json"
    check ".claude.json not group/world readable" bash -c "[ \$(( 0\$(stat -c %a $CONFIG_DIR/.claude.json) & 077 )) = 0 ]"
    if command -v jq >/dev/null; then
        check ".claude.json hasCompletedOnboarding is true" jq -e '.hasCompletedOnboarding == true' "$CONFIG_DIR/.claude.json"
    else
        check ".claude.json is the exact seed" grep -qxF '{"hasCompletedOnboarding":true}' "$CONFIG_DIR/.claude.json"
    fi
}

idempotency_checks() {
    local before after
    before=$(cd "$CONFIG_DIR" && ls -la --time-style=+%s . | sha256sum)
    if maybe_root /usr/local/share/claude-code-config-feature/entrypoint.sh 2>/tmp/ccc-rerun.log; then
        after=$(cd "$CONFIG_DIR" && ls -la --time-style=+%s . | sha256sum)
        check "entrypoint re-run changes nothing" test "$before" = "$after"
        check "entrypoint re-run is silent" test ! -s /tmp/ccc-rerun.log
        check "no moved-aside files in home" test -z "$(ls -A "$HOME" | grep pre-claude-code-config)"
    else
        echo "(skipping idempotency re-run: no root/sudo)"
    fi
}
