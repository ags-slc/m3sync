#!/bin/sh
# Target deletes a file source still has. Per the algorithm, the source's
# protected-list protects files newer than last-run AND any file appearing
# in the source's delta (< or > markers). A file that has been quiescent on
# the source for longer than last-run's age should NOT be protected, so the
# pull leg of full-duplex should propagate the deletion back to source.
#
# Expected behavior: after the sync, the file is gone from source.

setup_env

mkfile "${SRC}/victim.txt" "v"
mkfile "${SRC}/other.txt"  "o"
run_sync                          # initializes source, copies to target
assert_equal "${RUN_RC}" "0" || exit 1
run_sync                          # second run initializes target as m3sync dir
assert_equal "${RUN_RC}" "0" || exit 1

# Age everything so victim.txt is older than last-run (i.e. not protected).
touch_past "${SRC}/victim.txt" 600
touch_past "${SRC}/other.txt"  600
touch_past "${SRC}/.m3sync/last-run" 60

# Delete on the target.
rm "${DST}/victim.txt"

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# Document expected behavior: deletion propagates back to source.
assert_file_missing "${SRC}/victim.txt" || exit 1
assert_file_exists  "${SRC}/other.txt"  || exit 1
