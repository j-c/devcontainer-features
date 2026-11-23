# Manual test: Windows host (Docker Desktop with WSL2, VS Code Dev Containers)

CI can't reproduce Windows drvfs/9p mounts, so run this checklist on Windows. None of the steps prints credential contents.

## 0. Test before publishing (optional)

To try 2.0.0 without publishing it, copy `src/claude-code-config` into the project as `.devcontainer/claude-code-config`. Then reference the copy in `devcontainer.json`:

```jsonc
"features": { "./claude-code-config": {} }
```

## 1. Host baseline (PowerShell)

```powershell
Get-Item "$HOME\.claude\.credentials.json" -ErrorAction SilentlyContinue | Select-Object Length, LastWriteTime
```

Write down the result. Step 8 checks that it hasn't changed. "Not found" is fine.

## 2. Rebuild

In VS Code, run **Dev Containers: Rebuild Without Cache and Reopen in Container**.

- **Expect:** the container starts. It must start even if you temporarily rename `%USERPROFILE%\.claude`.

## 3. Mounts and environment (container terminal)

```bash
mount | grep -i claude
```

- **Expect:** exactly one line, `... on /usr/local/share/claude-code-config type ext4 ...`.
- **Expect:** no `9p` or `drvfs` lines, and no `.credentials.json` or `settings.json` lines.

```bash
env | grep CLAUDE_CONFIG_DIR
```

- **Expect:** no output.

## 4. Status helper

```bash
claude-code-config-status
```

Expect:
- `~/.claude: symlink -> /usr/local/share/claude-code-config`
- `~/.claude.json: symlink -> /usr/local/share/claude-code-config/.claude.json`
- `volume dir: directory, ..., vscode:vscode, mode 700`
- `save-path test: ok`
- the last line is `status: OK`. Before you log in, `.credentials.json: absent` is fine.

## 5. CLI login

```bash
claude
```

Then type `/login` and choose the subscription option. Finish the login in the browser.

- **Expect:** no "cannot write/save credentials" error.

Then run `claude-code-config-status` again. Expect:
- `.credentials.json: regular file, <n> bytes, vscode:vscode, mode 600`
- `OAuth token present, expires in <n> min`

## 6. VS Code extension

1. Run **Developer: Reload Window**.
   - **Expect:** the extension is already signed in, because it uses the same file.
2. To test the extension's own login path, sign out in the extension, then sign in again.
   - **Expect:** no "Failed to retrieve auth status after login".
   - **Expect:** `claude-code-config-status` still shows `vscode:vscode, mode 600`.

## 7. Token refresh persists (optional)

This forces a refresh by marking the access token as expired. It keeps a backup in `/tmp`, which is cleared on rebuild.

```bash
cd /usr/local/share/claude-code-config && cp -p .credentials.json /tmp/creds.bak && jq '.claudeAiOauth.expiresAt = 0' .credentials.json > .c.tmp && mv .c.tmp .credentials.json && chmod 600 .credentials.json
```

```bash
claude -p "say ok"
```

```bash
claude-code-config-status | grep -A1 credentials
```

- **Expect:** the token expires about 8 hours (480 min) in the future, and the file is still `vscode:vscode, mode 600`.

## 8. Persistence across a rebuild

Run **Rebuild Without Cache** again, then run `claude`.

- **Expect:** no login prompt and no onboarding screen.
- **Expect:** `claude-code-config-status` reports `status: OK`.

In PowerShell, repeat step 1.

- **Expect:** the same result as in step 1. The host file is never touched.

## 9. From the host (PowerShell)

```powershell
docker inspect $(docker ps -q --filter "label=devcontainer.local_folder=$PWD") --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
```

- **Expect:** the workspace bind mount, plus `volume docker-compose-files-claude-code-config -> /usr/local/share/claude-code-config`. Nothing else Claude-related.

## If something fails

Collect the following and send it with the failing step. None of it contains secrets.

- the output of `claude-code-config-status`
- the output of `mount | grep -i claude`
- the container log lines that start with `claude-code-config:`. Open them with **Dev Containers: Show Container Log**, or run `docker logs <id> 2>&1 | grep claude-code-config`.
