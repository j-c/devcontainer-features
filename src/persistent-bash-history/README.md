# Persistent Bash History (`persistent-bash-history`)

Persists bash command history across dev container rebuilds.

A per-project Docker named volume is mounted at `/commandhistory` and the user's
`.bashrc` is configured to append history immediately after each command
(`PROMPT_COMMAND='history -a'`), so history survives container rebuilds.

## Example usage

```jsonc
"features": {
    "ghcr.io/j-c/devcontainer-features/persistent-bash-history:1": {}
}
```

## Options

None.

## How it works

- Mounts a Docker volume named `${localWorkspaceFolderBasename}-bashhistory` at `/commandhistory`.
- Creates `/commandhistory/.bash_history` and chowns it to the remote user.
- Appends `HISTFILE=/commandhistory/.bash_history` and `PROMPT_COMMAND='history -a'` to the user's `.bashrc` (idempotent — safe to re-run).

## Notes

- Each project gets its own history volume (named after the workspace folder).
- The volume persists when the container is rebuilt; remove with `docker volume rm <project>-bashhistory`.
- Requires a non-root remote user (typically `vscode`); falls back to `root` if `_REMOTE_USER` is unset.
