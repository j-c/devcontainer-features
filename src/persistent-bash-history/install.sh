#!/usr/bin/env bash
set -euo pipefail

USERNAME="${_REMOTE_USER:-${USERNAME:-${_CONTAINER_USER:-root}}}"
HISTORY_DIR="/commandhistory"
HISTORY_FILE="${HISTORY_DIR}/.bash_history"
MARKER="# persistent-bash-history feature"

mkdir -p "$HISTORY_DIR"
touch "$HISTORY_FILE"
chown -R "${USERNAME}:${USERNAME}" "$HISTORY_DIR"

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
    echo "persistent-bash-history: could not resolve home directory for '$USERNAME'" >&2
    exit 1
fi

BASHRC="${USER_HOME}/.bashrc"

if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<EOF

${MARKER}
export PROMPT_COMMAND='history -a'
export HISTFILE=${HISTORY_FILE}
EOF
    chown "${USERNAME}:${USERNAME}" "$BASHRC"
fi
