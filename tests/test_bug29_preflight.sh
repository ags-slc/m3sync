#!/bin/sh
# BUG-29: m3sync didn't preflight for rsync (or ssh, for remote
# targets). A missing rsync produced a confusing 'command not found'
# mid-run; a missing ssh surfaced as a hang or a broken is_initialized
# check. Verify that a PATH-hidden rsync is surfaced up front with a
# clear diagnostic.

setup_env

# Build a tmp bin dir that symlinks every tool the script needs EXCEPT
# rsync. Then narrow PATH to it so the preflight must fire.
mkdir -p "${TESTDIR}/bin"
for _cmd in sh bash env date mkdir touch cp mv rm ls grep sed awk cksum \
            cut head tail sort hostname diff find chmod printf colrm stat \
            dirname basename mktemp which command test true false; do
    _p=$(command -v "${_cmd}" 2>/dev/null) || continue
    ln -s "${_p}" "${TESTDIR}/bin/${_cmd}" 2>/dev/null
done
PATH="${TESTDIR}/bin"
export PATH

mkfile "${SRC}/a.txt" "hi"

RUN_OUT=$("${M3SYNC}" "${SRC}" "${DST}" 2>&1)
RUN_RC=$?

if [ "${RUN_RC}" -eq 0 ]; then
    fail "m3sync succeeded with no rsync on PATH; expected refusal"
    exit 1
fi

# The preflight produces a specific m3sync-level log line BEFORE any
# subshell runs rsync. Before the fix, the failure surfaces as the
# shell's generic "rsync: command not found" at line ~700 instead.
case "${RUN_OUT}" in
    *"m3sync: error: "*"rsync"*) : ;;
    *)
        fail "preflight did not surface rsync as an m3sync error; got:
${RUN_OUT}"
        exit 1 ;;
esac

# The preflight must fire BEFORE the lock is acquired. Any lock-dir
# detritus means the script got past preflight.
assert_file_missing "${SRC}/.m3sync/lock" || exit 1
