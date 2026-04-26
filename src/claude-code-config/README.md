# Claude Code Config (`claude-code-config`)

Shares Claude Code configuration across dev container rebuilds and reuses the host's Claude credentials and `settings.json`.

A per-project Docker named volume is mounted at `/usr/local/share/claude-code-config` and symlinked to `~/.claude` for the resolved remote user, so config (projects, history, etc.) survives rebuilds and is shared across containers built from the same workspace folder. The host's `.credentials.json` and `settings.json` are bind-mounted into the volume so the dev container picks up the same login and settings as the host machine.

## Example usage

Pair it with the Claude Code CLI feature — this feature handles config persistence only, not CLI installation:

```jsonc
"features": {
    "ghcr.io/devcontainers-extra/features/claude-code:2": {},
    "ghcr.io/j-c/devcontainer-features/claude-code-config:1": {}
}
```

`installsAfter` ensures the CLI installs first when both are declared. The config feature also works standalone (volume + symlink + seed) if you install the CLI some other way.

## Options

None.

## How it works

- Mounts a Docker volume named `${localWorkspaceFolderBasename}-claude-code-config` at `/usr/local/share/claude-code-config`.
- Bind-mounts the host's `~/.claude/.credentials.json` and `~/.claude/settings.json` into that directory so credentials and settings come from the host.
- At install time, resolves the remote user from `_REMOTE_USER` / `_REMOTE_USER_HOME` (falling back to a common non-root user — `vscode`, `node`, `codespace` — then `_CONTAINER_USER`) and symlinks the volume to `~/.claude` for that user.
- Seeds `.claude.json` with `hasCompletedOnboarding: true` so the CLI doesn't trigger the onboarding flow on every fresh volume.
- Declares `installsAfter` for `ghcr.io/devcontainers-extra/features/claude-code` so the CLI is in place when the seed records its version, but doesn't require it.

## Notes

- The host paths use `${localEnv:HOME}${localEnv:USERPROFILE}` so they resolve correctly on both Unix (`HOME` set) and Windows (`USERPROFILE` set) hosts.
- The bind mount sources must exist on the host before the container starts — log into Claude Code on the host (`claude login`) at least once so `~/.claude/.credentials.json` and `~/.claude/settings.json` exist.
- Each project gets its own config volume (named after the workspace folder); remove with `docker volume rm <project>-claude-code-config`.
- The mount target (`/usr/local/share/claude-code-config`) is intentionally outside any user's home so the symlink approach works for any resolved remote user (`vscode`, `node`, `root`, etc.) without hardcoding paths in the feature manifest.
