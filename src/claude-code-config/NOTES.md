## What it does

Keeps Claude Code's per-user state (login, history, projects, settings, `~/.claude.json`) in a per-project Docker named volume, so it survives container rebuilds:

| Path in the container | Points to |
| --- | --- |
| `~/.claude` | symlink → `/usr/local/share/claude-code-config` (the volume) |
| `~/.claude.json` | symlink → `/usr/local/share/claude-code-config/.claude.json` |
| `/usr/local/share/claude-code-config` | named volume `${localWorkspaceFolderBasename}-claude-code-config`, owned by the remote user, mode `0700` |

**Nothing is mounted from the host.** You log in once inside the container (CLI `/login`, or the VS Code extension's sign-in) and the credentials, including every token refresh, are stored in the volume.

`CLAUDE_CONFIG_DIR` is deliberately **not** set: Claude Code uses its default locations, and the symlinks redirect them into the volume.

## Usage

```jsonc
"features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {},   // or ghcr.io/devcontainers-extra/features/claude-code:2
    "ghcr.io/j-c/devcontainer-features/claude-code-config:2": {}
}
```

Pin a major version (`:2`) or an exact one (`:2.0.0`). Don't use `:latest`.

This feature doesn't install the CLI. It declares `installsAfter` for both CLI features above, so the order doesn't matter. It works the same with image, Dockerfile and Docker Compose based dev containers, and with any `remoteUser` (`vscode`, `node`, `root`, or a custom user and home directory).

## How it works

- **Build time (`install.sh`).** Creates the mount point owned by the remote user with mode `0700`. Docker copies that owner and mode into a *fresh* volume on first mount. Also creates the two symlinks in the image and folds in any `~/.claude` or `~/.claude.json` that an earlier feature left in the image.
- **Every container start (feature `entrypoint`).** Runs as root before any lifecycle command and before VS Code's server and extensions start, so nothing can race it. Steps:
  - re-owns the volume and its contents to the remote user, which repairs volumes created by older versions or by a different `remoteUser`
  - forces `.credentials.json` to `0600` and strips group and other access from `.claude.json`
  - removes leftovers from 1.x (empty bind-mount placeholder files, dangling symlinks into the old host mount)
  - seeds `{"hasCompletedOnboarding":true}` into a missing `.claude.json`. On an existing file it sets the flag with `jq`; without `jq`, it leaves an existing file untouched.
  - repairs the symlinks
  - warns on stderr (container log) about anything it can't fix, such as a stray mount inside the volume or a `CLAUDE_CONFIG_DIR` override

  It never makes container start fail.
- **`claude-code-config-status`.** A diagnostic command. It prints only metadata: existence, type, size, owner, mode, JSON validity and token expiry. It never prints credential contents. It also replays the CLI's save sequence (create temp file → `rename()` → `chmod 600`) on a scratch file.

## Why not share the host's credentials?

Up to 1.x this feature tried to. It doesn't work reliably, for reasons verified against Claude Code 2.1.330 with `strace`:

1. **The CLI saves atomically.** It writes `.credentials.json.tmp.*` and `rename()`s it over the target, then runs `chmod 0600`.
   - **Bind-mounted file:** the `rename()` fails with `EBUSY`. The CLI then writes in place, but its `chmod` fails with `EPERM` whenever the file isn't owned by the container user, as on Windows where the drvfs/9p mount shows the file as `uid=0`. The CLI then reports that it couldn't save the credentials. The VS Code extension surfaces the same failure as *"Failed to retrieve auth status after login"*.
   - **Symlink to a host file:** the `rename()` replaces the symlink with a regular file, so sync to the host stops silently after the first refresh.
2. **A bind mount whose host source is missing aborts container creation.** Feature mounts are passed to Docker as `--mount type=bind`, and Docker refuses a missing source. On macOS Claude Code keeps credentials in the Keychain, so `~/.claude/.credentials.json` often doesn't exist on the host. A feature can't declare an `initializeCommand` to create the path first.
3. **Concurrent refreshes of one shared OAuth grant.** When host and container share one OAuth grant, either side refreshing can invalidate the other side's token if refresh tokens rotate. Separate logins avoid that.

### Alternative: a long-lived token from the host

If you'd rather not log in per project, run `claude setup-token` on the host, put the token in a host environment variable, and pass it through:

```jsonc
"remoteEnv": { "CLAUDE_CODE_OAUTH_TOKEN": "${localEnv:CLAUDE_CODE_OAUTH_TOKEN}" }
```

The CLI then ignores `.credentials.json`. Trade-offs:
- the token is visible to every process in the container
- it's inference-scoped, so some account features may be unavailable
- it lasts about a year and doesn't refresh

Whether the VS Code extension honours it hasn't been verified here.

## Settings

`~/.claude/settings.json` lives in the volume and isn't shared with the host. For settings that should apply to everyone working on a repo, commit `.claude/settings.json` in the project. For machine-wide settings, use a dotfiles repo.

## Per-OS behaviour

The same on Windows (Docker Desktop with WSL2), macOS and Linux hosts, because nothing on the host is read or written. The host's `~/.claude` can be missing, empty or populated, and the host's Keychain is irrelevant.

## Upgrading from 1.x

- Remove any `mounts` (in `devcontainer.json` or Compose files) that target `/usr/local/share/claude-code-config/...` or `/usr/local/share/claude-code-host-claude`. Stray mounts inside the volume make credential saves fail. The entrypoint and `claude-code-config-status` flag them.
- Rebuild the container. The existing volume is kept and repaired. Credentials that 1.x stored only as a symlink to the host aren't carried over, so log in once inside the container.

## Known limitations

- **Volume name collisions.** The volume is named after the workspace folder's basename, so two projects that share a folder name share a volume. This is unchanged from 1.x, to keep existing volumes.
- **`CLAUDE_CONFIG_DIR` overrides.** If you set `CLAUDE_CONFIG_DIR` yourself, Claude Code bypasses `~/.claude` and this feature has no effect. Non-default values also have known bugs, including VS Code extension login ([anthropics/claude-code#84267](https://github.com/anthropics/claude-code/issues/84267)) and paths that ignore the variable ([#97680](https://github.com/anthropics/claude-code/issues/97680)).
- **Non-root container user.** If the container user isn't root (for example Compose `user:`), the entrypoint can't repair ownership of an existing root-owned volume. It logs a warning.
- **Missing `jq`.** Without `jq`, an existing `.claude.json` that lacks `hasCompletedOnboarding` isn't modified.
- **One login per volume.** Each project volume holds its own login. Deleting the volume (`docker volume rm <folder>-claude-code-config`) logs you out of that project's containers.
