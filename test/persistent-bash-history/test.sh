#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

MARKER="# persistent-bash-history feature"

# The install script resolves the target user from build-time envvars
# (_REMOTE_USER etc.) that aren't necessarily set at test time. Rather
# than trying to re-derive that user, just locate the bashrc that
# contains the install marker — the install only writes to one.
BASHRC=""
for candidate in /root/.bashrc /home/*/.bashrc; do
    if [ -f "$candidate" ] && grep -qF "$MARKER" "$candidate"; then
        BASHRC="$candidate"
        break
    fi
done

check "history dir exists" test -d /commandhistory
check "history file exists" test -f /commandhistory/.bash_history
check "bashrc with marker found" test -n "$BASHRC"
check "bashrc exports HISTFILE to /commandhistory" grep -qF "HISTFILE=/commandhistory/.bash_history" "${BASHRC:-/dev/null}"
check "bashrc exports PROMPT_COMMAND for history -a" grep -qF "PROMPT_COMMAND='history -a'" "${BASHRC:-/dev/null}"

reportResults
