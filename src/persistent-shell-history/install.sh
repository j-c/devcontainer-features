#!/usr/bin/env bash
set -euo pipefail

USERNAME="${_REMOTE_USER:-${USERNAME:-${_CONTAINER_USER:-root}}}"
HISTORY_DIR="/commandhistory"
MARKER="# persistent-shell-history feature"

mkdir -p "$HISTORY_DIR"
chown -R "${USERNAME}:${USERNAME}" "$HISTORY_DIR"

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
    echo "persistent-shell-history: could not resolve home directory for '$USERNAME'" >&2
    exit 1
fi

configure_rc() {
    local rc_file="$1"
    local snippet="$2"
    local rc_dir
    rc_dir="$(dirname "$rc_file")"

    mkdir -p "$rc_dir"
    touch "$rc_file"

    if ! grep -qF "$MARKER" "$rc_file" 2>/dev/null; then
        printf '\n%s\n%s\n' "$MARKER" "$snippet" >> "$rc_file"
        chown "${USERNAME}:${USERNAME}" "$rc_file"
    fi
}

if command -v bash >/dev/null 2>&1; then
    BASH_HISTORY="${HISTORY_DIR}/.bash_history"
    touch "$BASH_HISTORY"
    chown "${USERNAME}:${USERNAME}" "$BASH_HISTORY"
    configure_rc "${USER_HOME}/.bashrc" \
        "export HISTFILE=${BASH_HISTORY}
export PROMPT_COMMAND='history -a'"
fi

if command -v zsh >/dev/null 2>&1; then
    ZSH_HISTORY="${HISTORY_DIR}/.zsh_history"
    touch "$ZSH_HISTORY"
    chown "${USERNAME}:${USERNAME}" "$ZSH_HISTORY"
    configure_rc "${USER_HOME}/.zshrc" \
        "export HISTFILE=${ZSH_HISTORY}
setopt INC_APPEND_HISTORY"
fi

if command -v fish >/dev/null 2>&1; then
    FISH_HISTORY_DIR="${HISTORY_DIR}/fish_history"
    mkdir -p "$FISH_HISTORY_DIR"
    chown -R "${USERNAME}:${USERNAME}" "$FISH_HISTORY_DIR"
    configure_rc "${USER_HOME}/.config/fish/config.fish" \
        "set -gx fish_history ${FISH_HISTORY_DIR}"
fi
