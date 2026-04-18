#!/bin/sh
# A file shared by both sides is deleted on the source. After sync, the
# target side deletes it too (rsync --delete on the push leg).

setup_env

mkfile "${SRC}/keep.txt" "k"
mkfile "${SRC}/gone.txt" "g"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists "${DST}/gone.txt" || exit 1

# Second run: initialize target as m3sync dir (happens in first run) and
# confirm we're in full-duplex now.
run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# Delete on the source, then sync.
rm "${SRC}/gone.txt"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1

assert_file_missing "${DST}/gone.txt" || exit 1
assert_file_exists  "${DST}/keep.txt" || exit 1
