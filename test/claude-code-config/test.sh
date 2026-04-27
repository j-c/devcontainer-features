#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

CONFIG_DIR="/usr/local/share/claude-code-config"

# Locate the user that the install script linked ~/.claude for.
# It writes to one of /root/.claude or /home/*/.claude — find the symlink
# that points at our config dir rather than re-deriving the user.
LINK=""
for candidate in /root/.claude /home/*/.claude; do
    if [ -L "$candidate" ] && [ "$(readlink "$candidate")" = "$CONFIG_DIR" ]; then
        LINK="$candidate"
        break
    fi
done

check "CLAUDE_CONFIG_DIR env var set" test "$CLAUDE_CONFIG_DIR" = "$CONFIG_DIR"
check "config volume mountpoint exists" test -d "$CONFIG_DIR"
check "claude.json seeded" test -f "$CONFIG_DIR/.claude.json"
check "claude.json has onboarding flag" grep -qF '"hasCompletedOnboarding":true' "$CONFIG_DIR/.claude.json"
check "~/.claude symlink found" test -n "$LINK"
check "~/.claude resolves into config volume" test -d "${LINK:-/dev/null}/"
# Bind mounts surface inside the volume (CI stubs them; tolerate absence locally).
if [ -e "$CONFIG_DIR/.credentials.json" ] || [ -e "$CONFIG_DIR/settings.json" ]; then
    check "credentials.json bind-mounted as a file" test -f "$CONFIG_DIR/.credentials.json"
    check "settings.json bind-mounted as a file" test -f "$CONFIG_DIR/settings.json"
fi

reportResults
