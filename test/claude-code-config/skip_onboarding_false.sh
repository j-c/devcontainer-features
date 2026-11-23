#!/usr/bin/env bash
source dev-container-features-test-lib
source "$(dirname "$0")/_common.sh"
common_checks
check "no .claude.json seeded when skipOnboarding=false" test ! -e "$CONFIG_DIR/.claude.json"
check "~/.claude.json symlink still in place" test -L "$HOME/.claude.json"
reportResults
