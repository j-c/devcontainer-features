#!/usr/bin/env bash
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
check "remote user is vscode" test "$ME" = vscode
check "running under compose" test -n "$COMPOSE_MARKER"
common_checks
onboarding_seeded_checks
idempotency_checks
reportResults
