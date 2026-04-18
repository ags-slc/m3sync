#!/bin/sh
# Test helper library for m3sync tests.
#
# Source this file from each test. It expects M3SYNC_ROOT to be set by the
# runner, and it will set M3SYNC (path to script) and TESTDIR (per-test tmp).

# Fail loudly if runner didn't wire in the script path.
: "${M3SYNC_ROOT:?M3SYNC_ROOT must be set by the test runner}"
M3SYNC="${M3SYNC_ROOT}/m3sync"
export M3SYNC

# TESTDIR is created by the runner; fall back to mktemp if invoked directly.
if [ -z "${TESTDIR:-}" ]; then
    TESTDIR=$(mktemp -d)
    export TESTDIR
    trap 'rm -rf "${TESTDIR}"' EXIT
fi

# setup_env: create SRC and DST sibling dirs under TESTDIR.
setup_env() {
    SRC="${TESTDIR}/source"
    DST="${TESTDIR}/target"
    mkdir -p "${SRC}" "${DST}"
    export SRC DST
}

# run_sync [args...]: invoke m3sync. With no args, uses "$SRC" "$DST".
# Captures stdout+stderr into RUN_OUT, exit code into RUN_RC.
run_sync() {
    if [ "$#" -eq 0 ]; then
        set -- "${SRC}" "${DST}"
    fi
    RUN_OUT=$("${M3SYNC}" "$@" 2>&1)
    RUN_RC=$?
    if [ "${VERBOSE:-0}" = "1" ]; then
        printf '[run_sync rc=%s] %s\n' "${RUN_RC}" "${RUN_OUT}" >&2
    fi
    return 0
}

# mkfile path content: create a file with parent dirs.
mkfile() {
    _path=$1; shift
    mkdir -p "$(dirname "${_path}")"
    printf '%s' "$*" > "${_path}"
}

# touch_past path seconds_ago: set mtime into the past.
touch_past() {
    _p=$1; _s=$2
    _t=$(($(date +%s) - _s))
    # BSD touch: -t [[CC]YY]MMDDhhmm[.SS]
    _stamp=$(date -r "${_t}" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@${_t}" '+%Y%m%d%H%M.%S')
    touch -t "${_stamp}" "${_p}"
}

# touch_future path seconds_ahead: set mtime into the future.
touch_future() {
    _p=$1; _s=$2
    _t=$(($(date +%s) + _s))
    _stamp=$(date -r "${_t}" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@${_t}" '+%Y%m%d%H%M.%S')
    touch -t "${_stamp}" "${_p}"
}

# fail msg: mark the current test as failed and return nonzero.
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

# assert_file_exists path
assert_file_exists() {
    [ -e "$1" ] || fail "expected file to exist: $1"
}

# assert_file_missing path
assert_file_missing() {
    [ ! -e "$1" ] || fail "expected file to be missing: $1"
}

# assert_file_contents path expected
assert_file_contents() {
    _got=$(cat "$1" 2>/dev/null) || { fail "cannot read $1"; return 1; }
    if [ "${_got}" != "$2" ]; then
        fail "contents of $1: expected [$2] got [${_got}]"
        return 1
    fi
}

# assert_equal a b
assert_equal() {
    if [ "$1" != "$2" ]; then
        fail "expected [$2] got [$1]"
        return 1
    fi
}

# assert_contains haystack needle — substring check.
assert_contains() {
    case "$1" in
        *"$2"*) return 0 ;;
        *)      fail "expected to contain [$2] but got [$1]"; return 1 ;;
    esac
}
