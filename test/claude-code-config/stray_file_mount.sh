#!/usr/bin/env bash
# Simulates the v1.0.0 / Windows failure: a host file (owned by another uid)
# bind-mounted onto .credentials.json inside the volume. The container must
# still start, and the feature must flag the problem rather than hide it.
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
T="$CONFIG_DIR/.credentials.json"
check "container started with stray mount" is_mountpoint "$T"
check "CLI-style save fails on the mounted file (EBUSY)" bash -c "! (source $(dirname "$0")/_common.sh; simulate_cli_save) 2>/dev/null"
check "status helper flags the stray mount" bash -c '! claude-code-config-status >/tmp/s.log 2>&1 && grep -q "extra mounts inside the volume" /tmp/s.log'
check "status helper does not print credential contents" bash -c '! grep -q STRAY-DUMMY /tmp/s.log'
# The harness copies both fixtures as the same host user, so if the entrypoint had
# chowned the mounted file its owner would now differ from the untouched sibling.
# (Comparing with our own uid is wrong when the host user is also uid 1000.)
SIB="$(dirname "$0")/.devcontainer/sibling.json"
echo "host fixture owners: mounted=$(stat -c %u "$T") sibling=$(stat -c %u "$SIB") container-user=$(id -u)"
check "entrypoint did not chown the host file" test "$(stat -c %u:%g "$T")" = "$(stat -c %u:%g "$SIB")"
reportResults
