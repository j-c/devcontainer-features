#!/usr/bin/env bash
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
check "remote user is node" test "$ME" = node
check "home is /home/node" test "$HOME" = /home/node
common_checks
onboarding_seeded_checks
idempotency_checks
reportResults
