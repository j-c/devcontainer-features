# devcontainer-features

A small collection of personal [dev container features](https://containers.dev/implementors/features/), published to GHCR.

## Features

| Feature | Description |
| --- | --- |
| [`persistent-bash-history`](src/persistent-bash-history) | Persists bash command history across dev container rebuilds via a per-project Docker named volume. |
| [`claude-code-config`](src/claude-code-config) | Shares Claude Code config across rebuilds via a per-project named volume and bind-mounts the host's Claude credentials into the container. |

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
    README.md                   # usage + options (auto-regenerated on release)
test/<feature-id>/
    test.sh                     # asserted with `devcontainer features test`
.github/workflows/
    validate.yaml               # PR validation
    test.yaml                   # runs feature tests across base images
    release.yaml                # publishes features to GHCR (manual dispatch)
```

## Releasing

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
