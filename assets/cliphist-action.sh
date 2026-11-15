#!/bin/sh
# Helper for the launcher clipboard history, wrapping cliphist.
#
# Usage: cliphist-action.sh <command> <db> [args...]
#
# <db> is the path of a cliphist database, or "-" for the default one.
# Flags must come before cliphist's own subcommand, hence the ch() helper.

set -eu

cmd=${1:?missing command}
db=${2:?missing database}
shift 2

# Non-default databases may live in a directory that doesn't exist yet
if [ "$db" != "-" ]; then
    mkdir -p "$(dirname "$db")"
fi

ch() {
    if [ "$db" = "-" ]; then
        cliphist "$@"
    else
        cliphist -db-path "$db" "$@"
    fi
}

# Whether a file is a list of file:// URIs, which is how file managers put copied files
# on the clipboard (text/uri-list)
is_files() {
    head -c 7 "$1" | grep -aq '^file://' || return 1
    head -c 65536 "$1" | tr -d '\r' | awk '
        NF && !/^#/ { n++; if ($0 !~ /^file:\/\//) bad = 1 }
        END { exit !(n > 0 && !bad) }'
}

# Writes the text of the clipboard to a file, which is a URI list if files were copied
clip_text() {
    if timeout 1 wl-paste --list-types 2>/dev/null | grep -qx 'text/uri-list' &&
        timeout 1 wl-paste --no-newline --type text/uri-list >"$1" 2>/dev/null &&
        is_files "$1"; then
        return 0
    fi
    timeout 1 wl-paste --no-newline --type text >"$1" 2>/dev/null
}

case "$cmd" in
list)
    # Older cliphist versions don't have -preview-width
    ch -preview-width 300 list 2>/dev/null || ch list
    ;;
text)
    # text <db> <id> <max-bytes>
    ch decode "$1" | head -c "$2"
    ;;
image)
    # image <db> <id> <out-file>: decode to a file once, reuse afterwards
    out=$2
    if [ ! -s "$out" ]; then
        mkdir -p "$(dirname "$out")"
        tmp="$out.$$"
        if ch decode "$1" >"$tmp"; then
            mv -f "$tmp" "$out"
        else
            rm -f "$tmp"
            exit 1
        fi
    fi
    ;;
copy)
    # copy <db> <id>: files are offered as text/uri-list so they paste as files
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    ch decode "$1" >"$tmp"
    if is_files "$tmp"; then
        wl-copy --type text/uri-list <"$tmp"
    else
        wl-copy <"$tmp"
    fi
    ;;
delete)
    # delete <db> <id>
    printf '%s\t\n' "$1" | ch delete
    ;;
prune)
    # prune <db> <cache-dir>: drop decoded images older than a day
    find "$1" -type f -mmin +1440 -delete 2>/dev/null || true
    ;;
wipe)
    # wipe <db>: clear the whole history of a database
    ch wipe
    ;;
current)
    # current <db> <max-bytes>: what the clipboard holds right now, as a line with the
    # kind (image or text) followed by the text, if any
    types=$(timeout 1 wl-paste --list-types 2>/dev/null) || exit 0
    if printf '%s\n' "$types" | grep -q '^image/'; then
        echo image
    elif printf '%s\n' "$types" | grep -qiE '^(text/|utf8_string$|string$|text$)'; then
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        clip_text "$tmp" || true
        echo text
        head -c "$1" "$tmp"
    fi
    ;;
active)
    # active <db> <id>...: print the ids whose content is exactly what the clipboard holds
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    clip_text "$tmp" || exit 0
    for id in "$@"; do
        if ch decode "$id" 2>/dev/null | cmp -s - "$tmp"; then
            echo "$id"
        fi
    done
    ;;
pin)
    # pin <source-db> <id> <pins-db>: copy an entry into the pins database
    mkdir -p "$(dirname "$2")"
    ch decode "$1" | cliphist -db-path "$2" store
    ;;
*)
    echo "cliphist-action: unknown command '$cmd'" >&2
    exit 2
    ;;
esac
