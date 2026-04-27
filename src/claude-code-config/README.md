# Claude Code Config (`claude-code-config`)

Shares Claude Code configuration across dev container rebuilds and reuses the host's Claude credentials and `settings.json`.

A per-project Docker named volume is mounted at `/usr/local/share/claude-code-config` and symlinked to `~/.claude` for the resolved remote user, so config (projects, history, etc.) survives rebuilds and is shared across containers built from the same workspace folder. The host's `settings.json` is bind-mounted into the volume. Credentials are handled via a `postStartCommand`: if the host's `.credentials.json` is non-empty, the active path inside the container is symlinked to it (so token refreshes write back to the host automatically); if only the container's volume has credentials, they are pushed to the host and then symlinked. Empty Docker-created placeholder files on the host are never propagated into the container.

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
- Bind-mounts the host's `~/.claude` directory (read-write) into a staging path used for credential handoff.
- At install time, resolves the remote user from `_REMOTE_USER` / `_REMOTE_USER_HOME` (falling back to a common non-root user — `vscode`, `node`, `codespace` — then `_CONTAINER_USER`) and symlinks the volume to `~/.claude` for that user.
- Seeds `.claude.json` with `hasCompletedOnboarding: true` so the CLI doesn't trigger the onboarding flow on every fresh volume.
- Runs a `postStartCommand` on every container start that symlinks `.credentials.json` in the volume to the host's copy when the host file is non-empty, so token refreshes are written back to the host. If the host file is absent or empty, no empty placeholder is propagated.
- Declares `installsAfter` for `ghcr.io/devcontainers-extra/features/claude-code` so the CLI is in place when the seed records its version, but doesn't require it.

## Notes

- The host paths use `${localEnv:HOME}${localEnv:USERPROFILE}` so they resolve correctly on both Unix (`HOME` set) and Windows (`USERPROFILE` set) hosts.
- For credentials: if you've logged into Claude Code on the host, they are picked up automatically. If not, log in inside the container — credentials are pushed to the host on next start and then kept in sync via symlink.
- Each project gets its own config volume (named after the workspace folder); remove with `docker volume rm <project>-claude-code-config`.
- The mount target (`/usr/local/share/claude-code-config`) is intentionally outside any user's home so the symlink approach works for any resolved remote user (`vscode`, `node`, `root`, etc.) without hardcoding paths in the feature manifest.
