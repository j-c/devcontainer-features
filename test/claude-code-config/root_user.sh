#!/usr/bin/env bash
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
check "remote user is root" test "$ME" = root
check "home is /root" test "$HOME" = /root
common_checks
onboarding_seeded_checks
idempotency_checks
reportResults
