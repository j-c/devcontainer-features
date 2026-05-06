# Persistent Shell History (`persistent-shell-history`)

Persists command history for all detected shells across dev container rebuilds.

A per-project Docker named volume is mounted at `/commandhistory`. At install time the script detects which shells are present (bash, zsh, fish) and configures each one to write history to the shared volume, so history survives container rebuilds.

## Example usage

```jsonc
"features": {
    "ghcr.io/j-c/devcontainer-features/persistent-shell-history:1": {}
}
```

## Options

None.

## How it works

- Mounts a Docker volume named `${localWorkspaceFolderBasename}-shellhistory` at `/commandhistory`.
- For each shell found on `PATH` at install time:
  - **bash** — sets `HISTFILE=/commandhistory/.bash_history` and `PROMPT_COMMAND='history -a'` in `~/.bashrc`.
  - **zsh** — sets `HISTFILE=/commandhistory/.zsh_history` and `setopt INC_APPEND_HISTORY` in `~/.zshrc`.
  - **fish** — sets `fish_history` to `/commandhistory/fish_history` in `~/.config/fish/config.fish`.
- All rc-file writes are idempotent (marker-guarded) — safe to re-run.

## Notes

- Each project gets its own history volume (named after the workspace folder).
- The volume persists when the container is rebuilt; remove with `docker volume rm <project>-shellhistory`.
- Requires a non-root remote user (typically `vscode`); falls back to `root` if `_REMOTE_USER` is unset.
- Only shells present at image-build time are configured; shells installed afterward will not be auto-configured.
