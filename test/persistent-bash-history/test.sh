#!/usr/bin/env bash
set -e

# Test library is bundled with the devcontainer CLI test harness
# and is automatically available on PATH at test time.
source dev-container-features-test-lib

# Detect which user the install ran as by looking at the owner of the
# history file the install script created. This avoids assuming `vscode`
# (the install falls back to `root` on base images without a remote user).
USERNAME="$(stat -c '%U' /commandhistory/.bash_history)"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
BASHRC="${USER_HOME}/.bashrc"

check "history dir exists" test -d /commandhistory
check "history file exists" test -f /commandhistory/.bash_history
check "bashrc exists for resolved user" test -f "$BASHRC"
check "bashrc has marker" grep -qF "# persistent-bash-history feature" "$BASHRC"
check "bashrc exports HISTFILE to /commandhistory" grep -qF "HISTFILE=/commandhistory/.bash_history" "$BASHRC"
check "bashrc exports PROMPT_COMMAND for history -a" grep -qF "PROMPT_COMMAND='history -a'" "$BASHRC"
if [ "$USERNAME" = "root" ]; then
    check "history file is writable by resolved user" test -w /commandhistory/.bash_history
else
    check "history file is writable by resolved user" sudo -u "$USERNAME" test -w /commandhistory/.bash_history
fi

reportResults
