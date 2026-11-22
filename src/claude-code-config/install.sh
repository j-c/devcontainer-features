#!/bin/sh
# Build-time half of claude-code-config. Runs as root during the image build,
# BEFORE the named volume exists, so it only prepares the image:
#   - the volume mount point, owned by the remote user (Docker copies the
#     directory's owner/mode into a *fresh* named volume on first mount);
#   - ~/.claude and ~/.claude.json symlinks into the mount point;
#   - the runtime entrypoint + status helper.
# Everything that depends on volume contents happens at runtime in entrypoint.sh.
set -eu

FEATURE_DIR="/usr/local/share/claude-code-config-feature"
CONFIG_DIR="/usr/local/share/claude-code-config"
SKIP_ONBOARDING="${SKIPONBOARDING:-true}"

# --- Resolve the runtime (remote) user -------------------------------------
USERNAME="${_REMOTE_USER:-}"
if [ -z "$USERNAME" ] || ! id "$USERNAME" >/dev/null 2>&1; then
    USERNAME=""
    for candidate in vscode node codespace; do
        if id "$candidate" >/dev/null 2>&1; then USERNAME="$candidate"; break; fi
    done
fi
USERNAME="${USERNAME:-${_CONTAINER_USER:-root}}"
id "$USERNAME" >/dev/null 2>&1 || { echo "claude-code-config: user '$USERNAME' does not exist" >&2; exit 1; }
USER_GROUP="$(id -gn "$USERNAME")"

USER_HOME="${_REMOTE_USER_HOME:-}"
if [ -z "$USER_HOME" ] || [ "$USERNAME" != "${_REMOTE_USER:-}" ]; then
    USER_HOME="$(getent passwd "$USERNAME" 2>/dev/null | cut -d: -f6 || true)"
fi
[ -n "$USER_HOME" ] || USER_HOME="/home/$USERNAME"
[ "$USERNAME" = root ] && [ "$USER_HOME" = "/home/root" ] && USER_HOME=/root

echo "claude-code-config: remote user=$USERNAME group=$USER_GROUP home=$USER_HOME"

# --- Mount point -----------------------------------------------------------
mkdir -p "$CONFIG_DIR"
chown "$USERNAME:$USER_GROUP" "$CONFIG_DIR"
chmod 0700 "$CONFIG_DIR"

mkdir -p "$USER_HOME"

# If an earlier feature (e.g. the CLI installer) left a real ~/.claude or
# ~/.claude.json in the image, fold it into the mount point so a fresh volume
# picks it up via copy-up. This is image-layer content, never user data from a
# running container, so removing the originals here is safe.
if [ -d "$USER_HOME/.claude" ] && [ ! -L "$USER_HOME/.claude" ]; then
    cp -a "$USER_HOME/.claude/." "$CONFIG_DIR/" 2>/dev/null || true
    rm -rf "$USER_HOME/.claude"
fi
if [ -f "$USER_HOME/.claude.json" ] && [ ! -L "$USER_HOME/.claude.json" ]; then
    [ -e "$CONFIG_DIR/.claude.json" ] || cp -p "$USER_HOME/.claude.json" "$CONFIG_DIR/.claude.json"
    rm -f "$USER_HOME/.claude.json"
fi
chown -R "$USERNAME:$USER_GROUP" "$CONFIG_DIR"

ln -sfn "$CONFIG_DIR" "$USER_HOME/.claude"
ln -sfn "$CONFIG_DIR/.claude.json" "$USER_HOME/.claude.json"
chown -h "$USERNAME:$USER_GROUP" "$USER_HOME/.claude" "$USER_HOME/.claude.json"

# --- Runtime pieces --------------------------------------------------------
mkdir -p "$FEATURE_DIR"
cat > "$FEATURE_DIR/env" <<EOF
CCC_USER='$USERNAME'
CCC_HOME='$USER_HOME'
CCC_CONFIG_DIR='$CONFIG_DIR'
CCC_SKIP_ONBOARDING='$SKIP_ONBOARDING'
EOF
install -m 0755 "$(dirname "$0")/entrypoint.sh" "$FEATURE_DIR/entrypoint.sh"
install -m 0755 "$(dirname "$0")/status.sh" /usr/local/bin/claude-code-config-status

# Remove the v1.x start script if a previous layer installed it.
rm -f /usr/local/bin/claude-code-config-start.sh
