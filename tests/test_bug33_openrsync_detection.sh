#!/bin/sh
# BUG-33: macOS ships openrsync, which silently drops --delete when -b is
# passed. m3sync must detect openrsync and degrade gracefully (no -b,
# backups disabled) while keeping deletions working.

setup_env

# Skip if we're running against GNU rsync. The degraded-path assertions
# below only apply when openrsync is the active rsync.
if ! rsync --version 2>/dev/null | head -n 1 | grep -q openrsync; then
    echo SKIP
    exit 0
fi

# A verbose run should emit the detection notice to stderr.
run_sync -v "${SRC}" "${DST}"
assert_contains "${RUN_OUT}" "openrsync detected" || exit 1

# And a full-duplex deletion cycle should now actually propagate.
# (Two files so deleting one doesn't also trip BUG-34: filtered_find exits
# non-zero on empty source under set -e.)
mkfile "${SRC}/keeper.txt" "k"
mkfile "${SRC}/toGo.txt" "x"
run_sync
run_sync  # second run initializes target and engages full-duplex
rm "${SRC}/toGo.txt"
run_sync
assert_file_missing "${DST}/toGo.txt" || exit 1
