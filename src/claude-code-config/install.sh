#!/bin/sh
set -e

USERNAME="${_REMOTE_USER:-${_CONTAINER_USER:-root}}"
USER_HOME="${_REMOTE_USER_HOME:-${_CONTAINER_USER_HOME:-/home/$USERNAME}}"

CONFIG_DIR="/usr/local/share/claude-code-config"
LINK_PATH="$USER_HOME/.claude"

mkdir -p "$CONFIG_DIR"
mkdir -p "$USER_HOME"

# Replace any existing ~/.claude with a symlink to the shared config volume.
# If a previous container created it as a regular dir, migrate its contents in.
if [ -L "$LINK_PATH" ]; then
    if [ "$(readlink "$LINK_PATH")" != "$CONFIG_DIR" ]; then
        rm -f "$LINK_PATH"
        ln -s "$CONFIG_DIR" "$LINK_PATH"
    fi
elif [ -e "$LINK_PATH" ]; then
    cp -an "$LINK_PATH/." "$CONFIG_DIR/" 2>/dev/null || true
    rm -rf "$LINK_PATH"
    ln -s "$CONFIG_DIR" "$LINK_PATH"
else
    ln -s "$CONFIG_DIR" "$LINK_PATH"
fi

# Hacky workaround to seed .claude.json so the CLI doesn't trigger the
# onboarding/login flow on every fresh container despite already having creds.
CLAUDE_JSON="$CONFIG_DIR/.claude.json"

CLI_VERSION=""
if command -v claude >/dev/null 2>&1; then
    CLI_VERSION="$(claude --version 2>/dev/null | awk '{print $1}')"
fi

if grep -qs '"hasCompletedOnboarding"' "$CLAUDE_JSON"; then
    : # already seeded — nothing to do
elif [ -s "$CLAUDE_JSON" ]; then
    # File has existing content (volume reuse) — insert flag before closing brace.
    tmp=$(mktemp)
    content=$(cat "$CLAUDE_JSON")
    printf '%s,"hasCompletedOnboarding":true}' "${content%\}}" > "$tmp"
    mv "$tmp" "$CLAUDE_JSON"
else
    # Fresh volume — write a minimal seed that the extension will merge into.
    printf '{"hasCompletedOnboarding":true,"lastOnboardingVersion":"%s"}' "$CLI_VERSION" > "$CLAUDE_JSON"
fi

# Chown only the dir/files we created — bind-mounted host files keep host ownership.
chown "$USERNAME:$USERNAME" "$CONFIG_DIR" 2>/dev/null || true
chown "$USERNAME:$USERNAME" "$CLAUDE_JSON" 2>/dev/null || true
chown -h "$USERNAME:$USERNAME" "$LINK_PATH" 2>/dev/null || true
chmod 600 "$CLAUDE_JSON" 2>/dev/null || true
