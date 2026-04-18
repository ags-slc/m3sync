#!/bin/sh
# BUG-02: rsync --delete wipes the target when the source is emptied
# (e.g. accidental `rm -rf *`). m3sync should refuse to run when the
# current scan finds zero user files but the previous-state knew about
# many; explicit override via M3SYNC_ALLOW_EMPTY_SOURCE=1.

setup_env

# Seed both sides with a few files.
mkfile "${SRC}/a.txt" "a"
mkfile "${SRC}/b.txt" "b"
mkfile "${SRC}/c.txt" "c"
run_sync
run_sync   # second run engages full-duplex

# Simulate an accidental wipe of the source tree.
rm "${SRC}/a.txt" "${SRC}/b.txt" "${SRC}/c.txt"

# Guard must fire: nonzero exit, target untouched.
run_sync
if [ "${RUN_RC}" -eq 0 ]; then
    fail "empty-source sync was allowed (rc=0); target would have been wiped"
    exit 1
fi
assert_file_exists "${DST}/a.txt" || exit 1
assert_file_exists "${DST}/b.txt" || exit 1
assert_file_exists "${DST}/c.txt" || exit 1

# With the override, the same sync proceeds and deletions propagate.
M3SYNC_ALLOW_EMPTY_SOURCE=1 run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_missing "${DST}/a.txt" || exit 1
assert_file_missing "${DST}/b.txt" || exit 1
assert_file_missing "${DST}/c.txt" || exit 1
