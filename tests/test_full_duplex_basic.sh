#!/bin/sh
# Both sides initialized. Target has a file that source lacks; after sync,
# source picks it up (this is the pull leg of full-duplex).

setup_env

# First pass: plain one-way sync to initialize both sides.
mkfile "${SRC}/shared.txt" "s1"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists "${DST}/.m3sync" || exit 1

# Now add a new file only on the target, and push the source mtime back so
# its protected-list (based on -newer last-run) doesn't mask the target file.
mkfile "${DST}/from_target.txt" "t1"
touch_past "${SRC}/shared.txt" 120
touch_past "${SRC}/.m3sync/last-run" 60

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

assert_file_exists   "${SRC}/from_target.txt"      || exit 1
assert_file_contents "${SRC}/from_target.txt" "t1" || exit 1
