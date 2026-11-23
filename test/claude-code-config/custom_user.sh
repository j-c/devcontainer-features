#!/usr/bin/env bash
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
check "remote user is dev" test "$ME" = dev
check "home is /srv/dev" test "$HOME" = /srv/dev
common_checks
onboarding_seeded_checks
idempotency_checks
reportResults
