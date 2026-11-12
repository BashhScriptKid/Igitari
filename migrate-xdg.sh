#!/usr/bin/env bash
# migrate-xdg.sh -- one-shot move of the pre-XDG install layout to the
# XDG one.
#
# Until the XDG migration, Igitari kept everything in one directory:
#
#     ~/.local/share/igitari/          <- the old LOCALPATH
#         .igitari-rc                  the RC file
#         .igitari_hist                command history
#         .update_pending              a pending-update notice
#         .update_new_sha              the SHA it referred to
#         ref.sha                      the updater's reference SHA
#
# The XDG layout splits those into their own homes:
#
#     ~/.config/igitari/.igitari-rc
#     ~/.local/state/igitari/.igitari_hist
#     ~/.local/state/igitari/.update_pending
#     ~/.local/state/igitari/.update_new_sha
#     ~/.local/share/igitari/ref.sha
#
# With the defaults, the data directory is the same path as the old
# directory, so ref.sha does not move -- it was already home. Everything
# else moves, and the old directory is removed only if it emptied.
#
# XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_DATA_HOME override the bases
# when set. The script moves files, it does not copy them. Nothing is
# overwritten: a file already in place is kept and the old one stays
# put, and every move is printed.
#
# Run it once. It does not talk to the network or to git.

set -euo pipefail

OLD="${HOME}/.local/share/igitari"

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/igitari"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/igitari"
DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/igitari"

if [[ ! -d "$OLD" ]]; then
    echo "Nothing to migrate -- no old install at ${OLD}."
    exit 0
fi

mkdir -p "${CONFIG_DIR}" "${STATE_DIR}" "${DATA_DIR}"

# ref.sha stays put when the old directory is (or is inside) the data
# directory; otherwise it moves like anything else.
declare -A MAP=(
    [.igitari-rc]="${CONFIG_DIR}/.igitari-rc"
    [.igitari_hist]="${STATE_DIR}/.igitari_hist"
    [.update_pending]="${STATE_DIR}/.update_pending"
    [.update_new_sha]="${STATE_DIR}/.update_new_sha"
)

if [[ "$OLD" != "$DATA_DIR" ]]; then
    MAP[ref.sha]="${DATA_DIR}/ref.sha"
else
    echo "ref.sha stays at ${DATA_DIR}/ref.sha (the data directory)."
fi

declare -a moved=() conflicts=() leftovers=()

for name in .igitari-rc .igitari_hist .update_pending .update_new_sha ref.sha; do
    [[ -n "${MAP[$name]:-}" ]] || continue
    src="${OLD}/${name}"
    dst="${MAP[$name]}"
    if [[ ! -e "$src" ]]; then
        continue
    fi
    if [[ -e "$dst" ]]; then
        conflicts+=("${name} -> already exists at ${dst}, kept, old one left in place")
        continue
    fi
    mv -- "$src" "$dst"
    moved+=("${name} -> ${dst}")
done

# Unknown files in the old directory are reported, never moved.
for src in "${OLD}"/* "${OLD}"/.*; do
    [[ -e "$src" ]] || continue
    name="${src##*/}"
    [[ -n "${MAP[$name]:-}" ]] && continue
    [[ $name == "ref.sha" && "$OLD" == "$DATA_DIR" ]] && continue
    leftovers+=("${name}")
done

if (( ${#moved[@]} > 0 )); then
    printf 'Moved %d file(s):\n' "${#moved[@]}"
    printf '  %s\n' "${moved[@]}"
else
    echo "Nothing to move."
fi

if (( ${#conflicts[@]} > 0 )); then
    printf 'Left alone (destination exists):\n'
    printf '  %s\n' "${conflicts[@]}"
fi

if (( ${#leftovers[@]} > 0 )); then
    printf 'Left in place (unknown to the migration):\n'
    printf '  %s\n' "${leftovers[@]}"
fi

# The old directory goes only when it emptied and it is not the data
# directory itself.
if [[ "$OLD" != "$DATA_DIR" && -z "$(find "$OLD" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    rmdir -- "$OLD"
    echo "Removed ${OLD}."
else
    echo "${OLD} stays (the data directory)."
fi
