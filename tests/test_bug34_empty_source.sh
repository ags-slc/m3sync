#!/bin/sh
# BUG-34: filtered_find's pipeline ends with grep -v ... which exits 1 on
# empty input. Under set -e this aborts the whole sync mid-run when the
# source tree has no user files left. The user's intent (propagate the
# "everything was deleted" state to the target) silently fails.

setup_env

# Start with one file, sync both ways to establish full-duplex.
mkfile "${SRC}/only.txt" "hello"
run_sync
run_sync

# Delete the last user file. Source is now user-empty (.m3sync remains).
# Pass the safety override (BUG-02) because this is an intentional wipe.
rm "${SRC}/only.txt"
export M3SYNC_ALLOW_EMPTY_SOURCE=1
run_sync
unset M3SYNC_ALLOW_EMPTY_SOURCE
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_missing "${DST}/only.txt" || exit 1
