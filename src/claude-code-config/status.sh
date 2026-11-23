#!/bin/sh
# claude-code-config-status: diagnostics for the claude-code-config feature.
# Prints only metadata (existence, type, size, owner, mode, JSON validity,
# token expiry in the past/future). Never prints credential contents.
# Exit status: 0 = healthy, 1 = problems found.

CCC_ENV=/usr/local/share/claude-code-config-feature/env
# shellcheck disable=SC1090
[ -r "$CCC_ENV" ] && . "$CCC_ENV"
V="${CCC_CONFIG_DIR:-/usr/local/share/claude-code-config}"
H="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
rc=0
bad() { echo "  PROBLEM: $*"; rc=1; }

meta() {
    if [ -L "$1" ]; then echo "symlink -> $(readlink "$1")"
    elif [ -e "$1" ]; then stat -c '%F, %s bytes, %U:%G, mode %a' "$1"
    else echo "absent"; fi
}
mounts_under() {
    awk -v p="$1" '{ m=$5; gsub(/\\040/, " ", m); if (m == p || index(m, p "/") == 1) print m " (" $(NF-2) ")" }' /proc/self/mountinfo 2>/dev/null
}

echo "user:               $(id -un) (uid $(id -u), gid $(id -g))"
echo "HOME:               $H"
echo "configured user:    ${CCC_USER:-?} (home ${CCC_HOME:-?})"
echo "CLAUDE_CONFIG_DIR:  ${CLAUDE_CONFIG_DIR:-<unset>}"
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && bad "CLAUDE_CONFIG_DIR is set; it bypasses ~/.claude and breaks VS Code extension login when non-default"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && echo "CLAUDE_CODE_OAUTH_TOKEN: set (overrides .credentials.json)"
echo "claude CLI:         $(command -v claude || echo 'not on PATH')"
echo
echo "mounts at/under $V:"
m=$(mounts_under "$V")
[ -n "$m" ] && echo "$m" | sed 's/^/  /' || bad "config volume not mounted at $V (nothing will persist)"
n=$(echo "$m" | grep -c . )
[ "${n:-0}" -gt 1 ] && bad "extra mounts inside the volume; remove them (they make credential saves fail with EBUSY/EPERM)"
echo
echo "~/.claude:          $(meta "$H/.claude")"
[ "$(readlink "$H/.claude" 2>/dev/null)" = "$V" ] || bad "~/.claude should be a symlink to $V"
echo "~/.claude.json:     $(meta "$H/.claude.json")"
[ "$(readlink "$H/.claude.json" 2>/dev/null)" = "$V/.claude.json" ] || bad "~/.claude.json should be a symlink to $V/.claude.json"
echo "volume dir:         $(meta "$V")"
[ -O "$V" ] || bad "$V is not owned by $(id -un)"
echo ".claude.json:       $(meta "$V/.claude.json")"
if [ -f "$V/.claude.json" ] && command -v jq >/dev/null 2>&1; then
    jq -e . "$V/.claude.json" >/dev/null 2>&1 && echo "                    valid JSON; hasCompletedOnboarding=$(jq -r '.hasCompletedOnboarding // "unset"' "$V/.claude.json")" \
        || bad ".claude.json is not valid JSON"
fi
c="$V/.credentials.json"
echo ".credentials.json:  $(meta "$c")"
if [ -L "$c" ]; then bad ".credentials.json is a symlink; the CLI replaces it on save"
elif [ -f "$c" ]; then
    [ -O "$c" ] || bad ".credentials.json not owned by $(id -un)"
    [ "$(stat -c %a "$c")" = 600 ] || bad ".credentials.json mode is not 600"
    if command -v jq >/dev/null 2>&1; then
        if jq -e '.claudeAiOauth.accessToken' "$c" >/dev/null 2>&1; then
            exp=$(jq -r '.claudeAiOauth.expiresAt // 0' "$c" 2>/dev/null)
            now=$(($(date +%s) * 1000))
            if [ "${exp:-0}" -gt "$now" ] 2>/dev/null; then echo "                    OAuth token present, expires in $(( (exp - now) / 60000 )) min"
            else echo "                    OAuth token present, access token expired (CLI refreshes on next use)"; fi
        else echo "                    no claudeAiOauth entry (not logged in via subscription)"; fi
    fi
fi
echo
# Reproduce the CLI's save sequence (create temp, rename over target, chmod 600)
# on a scratch file in the same directory.
t="$V/.ccc-savetest.$$"; r="$V/.ccc-savetest-target.$$"
step="create"
if (umask 077; : > "$t") 2>/dev/null && step="rename" && : > "$r" 2>/dev/null && mv -f "$t" "$r" 2>/dev/null \
   && step="chmod" && chmod 600 "$r" 2>/dev/null; then
    echo "save-path test:     ok (create + rename + chmod 600 in $V)"
else
    bad "save-path test failed at step: $step"
fi
rm -f "$t" "$r"
echo
[ "$rc" = 0 ] && echo "status: OK" || echo "status: PROBLEMS FOUND"
exit "$rc"
