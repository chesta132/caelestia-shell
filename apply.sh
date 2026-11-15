#!/usr/bin/env bash
# apply.sh - apply changes from the caelestia-shell repo to the shell installed on the system.
#
# Mirrors the shell "install" steps of CMakeLists.txt:
#   - assets components daemons modules services utils -> $DEST/
#   - assets/wrap_term_launch.sh is made executable
#   - shell.qml (settings.watchFiles: true -> false) -> $DEST/shell.qml
#   - LICENSE -> $DEST/LICENSE
#
# Use --rebuild (-R) to also clean-build and install the C++ plugin before applying.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo location:
#   REPO_NAME empty     -> current working directory
#   REPO_NAME relative  -> resolved relative to the directory this script lives in
#   REPO_NAME absolute  -> used as is
# (-r/--repo DIR on the command line overrides this; a relative DIR is resolved against the cwd.)
REPO_NAME="${CAELESTIA_REPO_NAME-}"

DEST="${CAELESTIA_DEST:-/etc/xdg/quickshell/caelestia}"
RELOAD_CMD="${CAELESTIA_RELOAD_CMD:-caelestia shell -r -d}"
INTERVAL="${CAELESTIA_INTERVAL:-0.5}"   # seconds between change checks while watching
DEBOUNCE="${CAELESTIA_DEBOUNCE:-0.4}"   # seconds to wait for changes to settle

SYNC_DIRS=(assets components daemons modules services utils)

MODE="apply"
PRUNE=1
DRY=0
REBUILD=0
REPO_ARG=""

# ---------- colors ----------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'; C_DIM=$'\e[2m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'; C_BLU=$'\e[34m'
else
    C_RESET=''; C_DIM=''; C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''
fi
info() { printf '%s[*]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YLW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

usage() {
    cat <<EOF
Usage: ${0##*/} [mode] [options]

Modes:
  apply, -a, --apply        Sync repo -> system, then reload (default)
  watch, -w, --watch        Watch the repo and sync on every change.
                            Reload manually: press 'r' (q to quit)
  auto,  -A, --auto         Watch the repo, sync and reload automatically on every change

Options:
  rebuild, -R, --rebuild    Remove build/, configure with CMake/Ninja (Release),
                            build, and sudo install before applying
  --no-prune                Keep files on the system that no longer exist in the repo
                            (default: they are deleted, only inside: ${SYNC_DIRS[*]})
  -n, --dry-run             Only show what would change, write nothing
  -r, --repo DIR            Repo location (overrides REPO_NAME)
  -d, --dest DIR            System location (default: $DEST)
  -h, --help                Show this help

Repo location (REPO_NAME, env CAELESTIA_REPO_NAME):
  empty (default)  -> current working directory
  relative path    -> relative to this script's directory ($SCRIPT_DIR)
  absolute path    -> used as is

Env: CAELESTIA_REPO_NAME, CAELESTIA_DEST, CAELESTIA_RELOAD_CMD, CAELESTIA_INTERVAL,
     CAELESTIA_DEBOUNCE, CAELESTIA_QML_EXTRA
Reload command: $RELOAD_CMD
EOF
}

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        apply|-a|--apply)       MODE="apply" ;;
        watch|-w|--watch)       MODE="watch" ;;
        auto|-A|--auto)         MODE="auto" ;;
        rebuild|-R|--rebuild)   REBUILD=1 ;;
        -p|--prune)             PRUNE=1 ;;          # default, kept for compatibility
        --no-prune)             PRUNE=0 ;;
        -n|--dry-run)           DRY=1 ;;
        -r|--repo)              REPO_ARG="${2:?--repo needs an argument}"; shift ;;
        -d|--dest)              DEST="${2:?--dest needs an argument}"; shift ;;
        -h|--help)              usage; exit 0 ;;
        *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
done

# ---------- resolve repo ----------
if [[ -n "$REPO_ARG" ]]; then
    REPO="$REPO_ARG"                      # relative to the cwd, like any CLI path
elif [[ -z "$REPO_NAME" ]]; then
    REPO="$PWD"
elif [[ "$REPO_NAME" == /* ]]; then
    REPO="$REPO_NAME"
else
    REPO="$SCRIPT_DIR/$REPO_NAME"
fi

# ---------- validation ----------
command -v rsync >/dev/null || { err "rsync is not installed"; exit 1; }
REPO_RESOLVED="$(cd "$REPO" 2>/dev/null && pwd)" || { err "Repo directory not found: $REPO"; exit 1; }
REPO="$REPO_RESOLVED"
[[ -f "$REPO/shell.qml" ]] || { err "$REPO/shell.qml does not exist, is this really the caelestia-shell repo? (see REPO_NAME / --repo)"; exit 1; }

# make sure --delete can never hit an important directory if DEST is wrong
case "${DEST%/}" in
    ""|/etc|/etc/xdg|/etc/xdg/quickshell|/usr|/usr/lib|/home|"$HOME") err "Unsafe DEST: '$DEST'"; exit 1 ;;
esac

# use sudo if DEST is not writable by the current user (or if rebuild needs sudo cmake --install)
SUDO=()
if [[ ! -d "$DEST" ]]; then
    PARENT="$(dirname "$DEST")"
    [[ -w "$PARENT" ]] || SUDO=(sudo)
elif [[ ! -w "$DEST" ]]; then
    SUDO=(sudo)
fi
if [[ (${#SUDO[@]} -gt 0 || $REBUILD -eq 1) && $EUID -ne 0 && $DRY -eq 0 ]]; then
    command -v sudo >/dev/null || { err "Root is needed but sudo is not available"; exit 1; }
    info "sudo is needed"
    sudo -v || exit 1
fi

# ---------- rebuild ----------
do_rebuild() {
    command -v cmake >/dev/null || { err "cmake is not installed"; return 1; }
    command -v ninja >/dev/null || { err "ninja is not installed"; return 1; }

    info "Rebuilding C++ plugin in ${C_DIM}$REPO${C_RESET}"
    if [[ $DRY -eq 1 ]]; then
        info "Dry run: rm -rf \"$REPO/build\""
        info "Dry run: cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release"
        info "Dry run: cmake --build build"
        info "Dry run: sudo cmake --install build"
        return 0
    fi

    (
        cd "$REPO" || exit 1
        info "Removing build/..."
        rm -rf build || exit 1

        info "Configuring CMake (Release)..."
        cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release || exit 1

        info "Building..."
        cmake --build build || exit 1

        info "Installing..."
        if [[ $EUID -eq 0 ]]; then
            cmake --install build || exit 1
        else
            sudo cmake --install build || exit 1
        fi
    ) || { err "Rebuild failed"; return 1; }

    ok "Rebuild & install finished"
    return 0
}

if [[ $REBUILD -eq 1 ]]; then
    do_rebuild || exit 1
fi

# The Caelestia plugin installed by a default `cmake --install` lives in /usr/local, which is not
# a default Qt import path. If it exists, add it to QML_IMPORT_PATH (for the preflight check and
# the reload). Override the location with CAELESTIA_QML_EXTRA.
LOCAL_QML="${CAELESTIA_QML_EXTRA:-/usr/local/lib/qt6/qml}"
if [[ -d "$LOCAL_QML/Caelestia" && ":${QML_IMPORT_PATH:-}:" != *":$LOCAL_QML:"* ]]; then
    export QML_IMPORT_PATH="$LOCAL_QML${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
    info "QML_IMPORT_PATH += $LOCAL_QML"
fi

# ---------- sync ----------
CHANGED_COUNT=0

sync_once() {
    CHANGED_COUNT=0
    local rs_opts=(-rlptD --out-format='%i|%n' --exclude=wrap_term_launch.sh)
    [[ $PRUNE -eq 1 ]] && rs_opts+=(--delete)
    [[ $DRY -eq 1 ]] && rs_opts+=(--dry-run)

    "${SUDO[@]}" mkdir -p "$DEST" 2>/dev/null || true

    local d out line
    for d in "${SYNC_DIRS[@]}"; do
        [[ -d "$REPO/$d" ]] || { warn "Skipping $d (not in the repo)"; continue; }
        # --chmod because checkouts/zips can carry odd permissions; match cmake (755 dirs, 644 files)
        out="$("${SUDO[@]}" rsync "${rs_opts[@]}" --chmod=D755,F644 "$REPO/$d/" "$DEST/$d/" 2>&1)" || {
            err "rsync failed in $d:"; printf '%s\n' "$out" >&2; return 1; }
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # skip directory entries that were only touched
            [[ "$line" == .d* ]] && continue
            if [[ "$line" == *deleting* ]]; then
                printf '  %s-%s %s/%s\n' "$C_RED" "$C_RESET" "$d" "${line#*|}"
            else
                printf '  %s~%s %s/%s\n' "$C_GRN" "$C_RESET" "$d" "${line#*|}"
            fi
            CHANGED_COUNT=$((CHANGED_COUNT + 1))
        done <<<"$out"
    done

    # shell.qml: watchFiles is turned off in the installed version (same as CMake)
    local tmp; tmp="$(mktemp)"
    sed 's/settings\.watchFiles: true/settings.watchFiles: false/' "$REPO/shell.qml" >"$tmp"
    if ! "${SUDO[@]}" cmp -s "$tmp" "$DEST/shell.qml" 2>/dev/null; then
        [[ $DRY -eq 0 ]] && "${SUDO[@]}" install -Dm644 "$tmp" "$DEST/shell.qml"
        printf '  %s~%s shell.qml\n' "$C_GRN" "$C_RESET"; CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi
    rm -f "$tmp"

    if [[ -f "$REPO/LICENSE" ]] && ! "${SUDO[@]}" cmp -s "$REPO/LICENSE" "$DEST/LICENSE" 2>/dev/null; then
        [[ $DRY -eq 0 ]] && "${SUDO[@]}" install -Dm644 "$REPO/LICENSE" "$DEST/LICENSE"
        printf '  %s~%s LICENSE\n' "$C_GRN" "$C_RESET"; CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi

    # wrap_term_launch.sh must be executable (excluded from rsync, handled separately)
    local wt_src="$REPO/assets/wrap_term_launch.sh" wt_dst="$DEST/assets/wrap_term_launch.sh"
    if [[ -f "$wt_src" ]] && { ! "${SUDO[@]}" cmp -s "$wt_src" "$wt_dst" 2>/dev/null || [[ ! -x "$wt_dst" ]]; }; then
        [[ $DRY -eq 0 ]] && "${SUDO[@]}" install -Dm755 "$wt_src" "$wt_dst"
        printf '  %s~%s assets/wrap_term_launch.sh\n' "$C_GRN" "$C_RESET"; CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi
    return 0
}

do_sync() {
    info "Sync ${C_DIM}$REPO -> $DEST${C_RESET}"
    sync_once || return 1
    if [[ $CHANGED_COUNT -eq 0 ]]; then
        ok "No changes"
    else
        ok "$CHANGED_COUNT file(s) changed"
        [[ $DRY -eq 1 ]] && warn "Dry run: nothing was written"
    fi
    return 0
}

# ---------- preflight: check the C++ plugin modules (Caelestia.*) are installed ----------
preflight_modules() {
    local dirs=() d
    if [[ -n "${CAELESTIA_QML_DIRS:-}" ]]; then
        IFS=: read -ra dirs <<<"$CAELESTIA_QML_DIRS"
    else
        # Only locations Qt actually reads. /usr/local is NOT a default import path.
        if command -v qtpaths6 >/dev/null; then
            d="$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null)"; [[ -n "$d" ]] && dirs+=("$d")
        fi
        [[ ${#dirs[@]} -eq 0 ]] && dirs=(/usr/lib/qt6/qml /usr/lib64/qt6/qml)
        # extra paths from the environment (quickshell uses them too if exported before reload)
        local extra=() e
        IFS=: read -ra extra <<<"${QML_IMPORT_PATH:-}:${QML2_IMPORT_PATH:-}"
        for e in "${extra[@]}"; do [[ -n "$e" ]] && dirs+=("$e"); done
    fi

    local missing=() uri rel found
    while IFS= read -r uri; do
        [[ -z "$uri" ]] && continue
        rel="${uri//./\/}"
        found=0
        for d in "${dirs[@]}"; do
            [[ -f "$d/$rel/qmldir" ]] && { found=1; break; }
        done
        [[ $found -eq 0 ]] && missing+=("$uri")
    done < <(cd "$REPO" && grep -rhoE --include=*.qml '^import Caelestia[A-Za-z0-9_.]*' . 2>/dev/null \
                | sed 's/^import //' | sort -u)

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "These C++ plugin modules are not installed: ${missing[*]}"
        warn "Searched in: ${dirs[*]}"
        for uri in "${missing[@]}"; do
            rel="${uri//./\/}"
            if [[ -f "/usr/local/lib/qt6/qml/$rel/qmldir" || -f "/usr/local/lib64/qt6/qml/$rel/qmldir" ]]; then
                warn "$uri exists in /usr/local, but that is not a Qt import path. Reinstall with -DCMAKE_INSTALL_PREFIX=/usr"
                break
            fi
        done
        warn "apply.sh only copies QML. Build + install the plugin: cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr && cmake --build build && sudo cmake --install build"
        return 1
    fi
    return 0
}

do_reload() {
    [[ $DRY -eq 1 ]] && { info "Dry run: skipping reload ($RELOAD_CMD)"; return 0; }
    preflight_modules || warn "Reloading anyway, but loading will most likely fail (see the warnings above)"
    info "Reload: $RELOAD_CMD"
    # shellcheck disable=SC2086
    if $RELOAD_CMD; then ok "Reload finished"; else warn "Reload command exited with an error"; fi
}

# ---------- repo fingerprint (change detection without needing inotify) ----------
fingerprint() {
    (
        cd "$REPO" || exit 1
        find "${SYNC_DIRS[@]}" shell.qml LICENSE -type f -printf '%p %T@ %s\n' 2>/dev/null | LC_ALL=C sort
    ) | md5sum
}

# ---------- modes ----------
cleanup() { [[ -t 0 ]] && stty echo 2>/dev/null; printf '\n'; info "Bye"; exit 0; }

wait_stable() {
    # wait until the repo is quiet (editors can write several files in a row)
    local prev cur
    prev="$(fingerprint)"
    while sleep "$DEBOUNCE"; do
        cur="$(fingerprint)"
        [[ "$cur" == "$prev" ]] && break
        prev="$cur"
    done
    LAST_FP="$prev"
}

case "$MODE" in
    apply)
        do_sync || exit 1
        do_reload
        ;;

    watch|auto)
        trap cleanup INT TERM
        do_sync || exit 1
        if [[ "$MODE" == "auto" ]]; then
            do_reload
            info "Watching ${C_DIM}$REPO${C_RESET} (auto reload) - Ctrl+C to quit"
        else
            info "Watching ${C_DIM}$REPO${C_RESET} (manual reload) - [r] reload  [s] force sync  [q] quit"
        fi

        LAST_FP="$(fingerprint)"
        while true; do
            key=""
            if [[ -t 0 ]]; then
                IFS= read -rsn1 -t "$INTERVAL" key || true
            else
                sleep "$INTERVAL"
            fi

            case "$key" in
                r|R) do_sync; do_reload; LAST_FP="$(fingerprint)"; continue ;;
                s|S) do_sync; LAST_FP="$(fingerprint)"; continue ;;
                q|Q) cleanup ;;
            esac

            cur="$(fingerprint)"
            if [[ "$cur" != "$LAST_FP" ]]; then
                wait_stable
                printf '%s--- %s ---%s\n' "$C_DIM" "$(date +%H:%M:%S)" "$C_RESET"
                do_sync
                if [[ "$MODE" == "auto" ]]; then
                    [[ $CHANGED_COUNT -gt 0 ]] && do_reload
                else
                    [[ $CHANGED_COUNT -gt 0 ]] && warn "Synced, press [r] to reload"
                fi
            fi
        done
        ;;
esac
