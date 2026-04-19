#!/bin/sh
# m3sync installer.
#
# Intended usage:
#   curl -fsSL https://raw.githubusercontent.com/ags-slc/m3sync/master/install.sh | sh
#
# Or with options (pass them after `sh -s --`):
#   curl -fsSL .../install.sh | sh -s -- --prefix /custom/bin --ref v1.0
#
# Options:
#   --prefix DIR   Install target directory (default: $HOME/.local/bin).
#                  Also configurable via M3SYNC_PREFIX.
#   --ref REF      Git ref (branch, tag, or commit SHA) to fetch.
#                  Default: master. Also configurable via M3SYNC_REF.
#   --help         Show this text and exit.
#
# Environment:
#   M3SYNC_PREFIX   Overrides --prefix.
#   M3SYNC_REF      Overrides --ref.
#   M3SYNC_URL_BASE Overrides the raw-content URL base for testing or
#                   for a fork (default:
#                   https://raw.githubusercontent.com/ags-slc/m3sync).
#
# The installer requires curl (and the usual POSIX tools). m3sync itself
# needs rsync at runtime; on macOS the shipped openrsync is auto-detected
# and works out of the box.

set -eu

PREFIX="${M3SYNC_PREFIX:-${HOME}/.local/bin}"
REF="${M3SYNC_REF:-master}"
URL_BASE="${M3SYNC_URL_BASE:-https://raw.githubusercontent.com/ags-slc/m3sync}"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX=$2; shift 2 ;;
        --ref)    REF=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'install.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

if ! command -v curl > /dev/null 2>&1; then
    printf 'install.sh: curl is required but not found on PATH\n' >&2
    exit 1
fi

mkdir -p "${PREFIX}"

URL="${URL_BASE}/${REF}/m3sync"
TARGET="${PREFIX}/m3sync"

printf 'Downloading m3sync (ref=%s) to %s\n' "${REF}" "${TARGET}"
if ! curl -fsSL "${URL}" -o "${TARGET}.tmp"; then
    printf 'install.sh: download failed from %s\n' "${URL}" >&2
    rm -f "${TARGET}.tmp"
    exit 1
fi

# Sanity-check that what we downloaded looks like the m3sync script.
if ! head -n 1 "${TARGET}.tmp" | grep -q '^#!'; then
    printf 'install.sh: downloaded file does not start with a shebang; aborting\n' >&2
    printf 'first bytes: %s\n' "$(head -c 80 "${TARGET}.tmp")" >&2
    rm -f "${TARGET}.tmp"
    exit 1
fi

mv "${TARGET}.tmp" "${TARGET}"
chmod +x "${TARGET}"

printf '\nInstalled m3sync at %s\n' "${TARGET}"

case ":${PATH}:" in
    *":${PREFIX}:"*)
        : ;;
    *)
        printf '\nNote: %s is not on your PATH. Add this to your shell init:\n' "${PREFIX}"
        # ${PATH} here is literal text we want the user to copy into
        # their shell rc; it must NOT expand at installer runtime.
        # shellcheck disable=SC2016
        printf '    export PATH="%s:${PATH}"\n' "${PREFIX}" ;;
esac

# Show that the binary works.
printf '\n'
"${TARGET}" -h | head -n 3
