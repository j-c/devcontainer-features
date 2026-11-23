#!/bin/sh
# Runtime half of claude-code-config. Declared as the feature's "entrypoint",
# so the dev container CLI runs it on EVERY container start, as the container
# user (normally root), before any lifecycle command and before VS Code's
# server/extensions start. It must never block container start: every step is
# best-effort, problems are reported on stderr (container log), exit is 0.
#
# It never reads out, prints or copies credential contents anywhere except
# within the volume, and never loosens permissions.

CCC_ENV=/usr/local/share/claude-code-config-feature/env
# shellcheck disable=SC1090
[ -r "$CCC_ENV" ] && . "$CCC_ENV"
U="${CCC_USER:-root}"
H="${CCC_HOME:-/root}"
V="${CCC_CONFIG_DIR:-/usr/local/share/claude-code-config}"
SKIP_ONBOARDING="${CCC_SKIP_ONBOARDING:-true}"

log() { echo "claude-code-config: $*" >&2; }

# Mount points at or below a path, from /proc/self/mountinfo (field 5).
mounts_under() {
    awk -v p="$1" '{ m=$5; gsub(/\\040/, " ", m); if (m == p || index(m, p "/") == 1) print m }' \
        /proc/self/mountinfo 2>/dev/null
}
is_mountpoint() { mounts_under "$1" | grep -qxF "$1"; }

ts() { date +%Y%m%d%H%M%S; }

# Move something out of the way instead of deleting it (it may be user data).
move_aside() {
    dest="$1.pre-claude-code-config.$(ts)"
    if mv "$1" "$dest" 2>/dev/null; then log "moved existing $1 to $dest"; else log "WARNING: could not move $1 aside"; fi
}

main() {
    ME=$(id -u)
    UID_T=$(id -u "$U" 2>/dev/null) || { log "WARNING: user '$U' not found; skipping setup"; return 0; }
    GID_T=$(id -g "$U")
    CAN_CHOWN=0
    [ "$ME" = 0 ] && CAN_CHOWN=1
    if [ "$ME" != 0 ] && [ "$ME" != "$UID_T" ]; then
        log "WARNING: running as uid $ME (not root, not $U); ownership cannot be repaired"
    fi

    [ -d "$V" ] || { log "WARNING: $V missing; skipping setup"; return 0; }
    is_mountpoint "$V" || log "WARNING: $V is not a mount; config will NOT survive a rebuild"

    # Anything mounted *inside* the volume (e.g. a leftover single-file bind of
    # the host's .credentials.json from v1) breaks the CLI's atomic save
    # (rename -> EBUSY) and usually its chmod (EPERM on a host-owned file).
    STRAY=$(mounts_under "$V" | grep -vxF "$V")
    if [ -n "$STRAY" ]; then
        for m in $STRAY; do
            log "WARNING: stray mount inside the config volume: $m"
        done
        log "WARNING: remove these mounts from devcontainer.json / docker-compose; Claude login cannot save credentials while they exist"
    fi

    # --- Ownership / mode of the volume -----------------------------------
    if [ "$CAN_CHOWN" = 1 ]; then
        chown "$UID_T:$GID_T" "$V" 2>/dev/null
        chmod 0700 "$V" 2>/dev/null
        # Existing volumes may hold root-owned files (v1 mount placeholders, or a
        # different remoteUser previously). Skipped entirely when something is
        # mounted inside: a same-filesystem bind is not excluded by -xdev, and
        # chowning a host file is never acceptable.
        if [ -z "$STRAY" ]; then
            find "$V" -xdev \( ! -user "$UID_T" -o ! -group "$GID_T" \) -exec chown -h "$UID_T:$GID_T" {} + 2>/dev/null
        fi
    fi

    # --- Legacy v1 leftovers ----------------------------------------------
    for f in .credentials.json settings.json; do
        p="$V/$f"
        is_mountpoint "$p" && continue
        if [ -L "$p" ]; then
            # v1.x symlinked .credentials.json at the host bind mount. The CLI
            # replaces symlinks on save anyway; make it a real file now.
            if [ -f "$p" ] && [ -s "$p" ]; then
                tmp="$p.ccc-tmp.$$"
                if (umask 077; cp "$p" "$tmp") 2>/dev/null && mv -f "$tmp" "$p"; then
                    log "replaced symlink $p with a regular-file copy"
                else
                    rm -f "$tmp"; log "WARNING: could not replace symlink $p"
                fi
            else
                rm -f "$p" && log "removed dangling symlink $p"
            fi
        elif [ -f "$p" ] && [ ! -s "$p" ]; then
            # Empty file = Docker's bind-mount placeholder left in the volume by v1.0.0.
            rm -f "$p" && log "removed empty placeholder $p"
        fi
    done

    # --- Secrets: owner = runtime user, never more open than 0600 -----------
    c="$V/.credentials.json"
    if [ -f "$c" ] && [ ! -L "$c" ] && ! is_mountpoint "$c"; then
        [ "$CAN_CHOWN" = 1 ] && chown "$UID_T:$GID_T" "$c" 2>/dev/null
        chmod 0600 "$c" 2>/dev/null || log "WARNING: could not chmod 0600 $c"
    fi
    j="$V/.claude.json"
    if [ -f "$j" ] && [ ! -L "$j" ]; then
        chmod go-rwx "$j" 2>/dev/null
    fi

    # --- ~/.claude.json lives in the volume ----------------------------------
    # Adopt a real file from $HOME (e.g. written by a tool before the symlink
    # existed) when the volume has none, rather than seeding over it.
    if [ ! -e "$j" ] && [ ! -L "$j" ] && [ -f "$H/.claude.json" ] && [ ! -L "$H/.claude.json" ]; then
        mv "$H/.claude.json" "$j" && log "moved $H/.claude.json into the volume"
        [ "$CAN_CHOWN" = 1 ] && chown "$UID_T:$GID_T" "$j" 2>/dev/null
        chmod go-rwx "$j" 2>/dev/null
    fi
    if [ "$SKIP_ONBOARDING" = true ]; then
        if [ ! -e "$j" ] && [ ! -L "$j" ]; then
            (umask 077; printf '{"hasCompletedOnboarding":true}\n' > "$j.ccc-tmp.$$") && mv -f "$j.ccc-tmp.$$" "$j"
            [ "$CAN_CHOWN" = 1 ] && chown "$UID_T:$GID_T" "$j" 2>/dev/null
        fi
        if [ -f "$j" ] && command -v jq >/dev/null 2>&1; then
            if jq -e 'type == "object"' "$j" >/dev/null 2>&1; then
                if ! jq -e '.hasCompletedOnboarding == true' "$j" >/dev/null 2>&1; then
                    tmp="$j.ccc-tmp.$$"
                    if (umask 077; jq '.hasCompletedOnboarding = true' "$j" > "$tmp") 2>/dev/null; then
                        [ "$CAN_CHOWN" = 1 ] && chown "$UID_T:$GID_T" "$tmp" 2>/dev/null
                        mv -f "$tmp" "$j"
                    else
                        rm -f "$tmp"
                    fi
                fi
            else
                log "WARNING: $j is not a JSON object; leaving it untouched"
            fi
        fi
        # Without jq an existing file is left alone: string-splicing JSON is unsafe.
    fi

    # --- Home symlinks (also present in the image; repaired if needed) -------
    [ -d "$H" ] || { log "WARNING: home $H missing; cannot link"; return 0; }
    link() { # link <path-in-home> <target>
        if [ -L "$1" ]; then
            [ "$(readlink "$1")" = "$2" ] && return 0
            rm -f "$1"
        elif [ -e "$1" ]; then
            if [ -d "$1" ]; then cp -an "$1/." "$V/" 2>/dev/null; fi
            move_aside "$1"
        fi
        ln -s "$2" "$1" && { [ "$CAN_CHOWN" = 1 ] && chown -h "$UID_T:$GID_T" "$1" 2>/dev/null; }
        return 0
    }
    link "$H/.claude" "$V"
    link "$H/.claude.json" "$V/.claude.json"

    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "$CLAUDE_CONFIG_DIR" != "$H/.claude" ] && \
        log "WARNING: CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR overrides ~/.claude; config may not persist and VS Code extension login is known to fail with a non-default CLAUDE_CONFIG_DIR"
    return 0
}

main
# Entrypoints are chained by the dev container CLI; only exec when given a command.
[ "$#" -gt 0 ] && exec "$@"
exit 0
