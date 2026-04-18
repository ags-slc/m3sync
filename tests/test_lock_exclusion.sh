#!/bin/sh
# Two overlapping syncs: the second must be rejected because the first
# holds .m3sync/lock. We simulate this by pre-creating the lock dir.

setup_env

mkfile "${SRC}/a.txt" "a"
run_sync                                # initializes .m3sync in source
assert_equal "${RUN_RC}" "0" || exit 1

# Pre-create the lock (as if another sync were mid-flight).
mkdir "${SRC}/.m3sync/lock" || { fail "could not pre-create lock"; exit 1; }

RUN_OUT=$("${M3SYNC}" "${SRC}" "${DST}" 2>&1); RUN_RC=$?

# The second run must fail.
if [ "${RUN_RC}" -eq 0 ]; then
    fail "expected nonzero exit when lock exists, got 0 (out: ${RUN_OUT})"
    exit 1
fi

# Lock dir must still be there — the rejected run shouldn't have released it.
assert_file_exists "${SRC}/.m3sync/lock" || exit 1
