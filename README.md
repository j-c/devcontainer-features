# devcontainer-features

A small collection of personal [dev container features](https://containers.dev/implementors/features/), published to GHCR.

## Features

| Feature | Description |
| --- | --- |
| [`persistent-bash-history`](src/persistent-bash-history) | Persists bash command history across dev container rebuilds via a per-project Docker named volume. |
| [`persistent-shell-history`](src/persistent-shell-history) | Persists command history for all detected shells (bash, zsh, fish) across dev container rebuilds via a per-project Docker named volume. |
| [`claude-code-config`](src/claude-code-config) | Persists Claude Code config and credentials (`~/.claude`, `~/.claude.json`) across rebuilds in a per-project named volume. Nothing is mounted from the host. Pair with a Claude Code CLI feature. |

## Usage

Reference a feature in your `.devcontainer/devcontainer.json`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/j-c/devcontainer-features/persistent-bash-history:1": {}
    }
}
```

See each feature's README for available options.

## Repository layout

```
src/<feature-id>/
    devcontainer-feature.json   # feature metadata + mounts/options
    install.sh                  # runs at container build
    NOTES.md                    # hand-written docs, appended to the generated README
    README.md                   # usage + options (auto-regenerated on release)
test/<feature-id>/
    test.sh                     # asserted with `devcontainer features test`
    scenarios.json + <name>.sh  # scenario tests (optional per-scenario fixture dir <name>/)
.github/workflows/
    validate.yaml               # PR validation
    test.yaml                   # runs feature tests across base images
    release.yaml                # publishes features to GHCR (manual dispatch)
```

## Releasing

**Bump `version` in `devcontainer-feature.json` for every change you want published.** The publish step skips any version that already exists in the registry (`Version X already exists, skipping`), so an unbumped change never reaches GHCR. Use semver: a breaking change means a major bump.

Features are published to GHCR by manually dispatching the [`release.yaml`](.github/workflows/release.yaml) workflow on `main`. The workflow also opens a PR with regenerated feature READMEs.

After the first publish, set each package's visibility to **public** under [package settings](https://github.com/users/j-c/packages) — otherwise consumers will hit auth errors when pulling.

## Local testing

Install the devcontainer CLI and run a feature's test against any base image:

```bash
npm install -g @devcontainers/cli
devcontainer features test \
    --features persistent-bash-history \
    --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
    .
```

## License

[MIT](LICENSE)
