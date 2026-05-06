#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

MARKER="# persistent-shell-history feature"

check "history dir exists" test -d /commandhistory

if command -v bash >/dev/null 2>&1; then
    BASHRC=""
    for candidate in /root/.bashrc /home/*/.bashrc; do
        if [ -f "$candidate" ] && grep -qF "$MARKER" "$candidate"; then
            BASHRC="$candidate"
            break
        fi
    done
    check "bash: rc file with marker found" test -n "$BASHRC"
    check "bash: history file exists" test -f /commandhistory/.bash_history
    check "bash: HISTFILE set in rc" grep -qF "HISTFILE=/commandhistory/.bash_history" "${BASHRC:-/dev/null}"
    check "bash: PROMPT_COMMAND set in rc" grep -qF "PROMPT_COMMAND='history -a'" "${BASHRC:-/dev/null}"
fi

if command -v zsh >/dev/null 2>&1; then
    ZSHRC=""
    for candidate in /root/.zshrc /home/*/.zshrc; do
        if [ -f "$candidate" ] && grep -qF "$MARKER" "$candidate"; then
            ZSHRC="$candidate"
            break
        fi
    done
    check "zsh: rc file with marker found" test -n "$ZSHRC"
    check "zsh: history file exists" test -f /commandhistory/.zsh_history
    check "zsh: HISTFILE set in rc" grep -qF "HISTFILE=/commandhistory/.zsh_history" "${ZSHRC:-/dev/null}"
    check "zsh: INC_APPEND_HISTORY set in rc" grep -qF "setopt INC_APPEND_HISTORY" "${ZSHRC:-/dev/null}"
fi

if command -v fish >/dev/null 2>&1; then
    FISH_CONFIG=""
    for candidate in /root/.config/fish/config.fish /home/*/.config/fish/config.fish; do
        if [ -f "$candidate" ] && grep -qF "$MARKER" "$candidate"; then
            FISH_CONFIG="$candidate"
            break
        fi
    done
    check "fish: config file with marker found" test -n "$FISH_CONFIG"
    check "fish: history dir exists" test -d /commandhistory/fish_history
    check "fish: fish_history set in config" grep -qF "set -gx fish_history /commandhistory/fish_history" "${FISH_CONFIG:-/dev/null}"
fi

reportResults
