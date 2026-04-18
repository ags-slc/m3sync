#!/bin/sh
# BUG-06: filtered_find uses `grep -v ${cf_dir}` which matches ".m3sync"
# as a substring anywhere in the path. A legitimate user file whose name
# happens to contain "m3sync" (e.g. notes-m3sync.txt) is dropped from
# current-state, never protected, and can be silently deleted on the next
# full-duplex cycle.

setup_env

# notes-m3sync.txt is a normal user file; it must survive sync cycles.
mkfile "${SRC}/notes-m3sync.txt" "should stay"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists "${DST}/notes-m3sync.txt" || exit 1

# Second cycle (full-duplex) must also preserve the file and carry its
# name into current-state (so a future delta can reason about it).
run_sync
assert_file_exists "${DST}/notes-m3sync.txt" || exit 1
grep -q '^notes-m3sync\.txt$' "${SRC}/.m3sync/current-state" \
    || fail "notes-m3sync.txt missing from current-state (BUG-06 not fixed)"
