#!/usr/bin/env bash
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
common_checks
onboarding_seeded_checks
idempotency_checks
reportResults
