#!/bin/sh
# -n (dry run) should not leave a permanent change to current-state. The
# script moves current-state -> previous-state, writes a new current-state,
# and under dry-run must restore the previous current-state.

setup_env

mkfile "${SRC}/a.txt" "first"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# Capture the post-first-run current-state snapshot.
before=$(cat "${SRC}/.m3sync/current-state")

# Add a file and run with -n; target should NOT receive it and current-state
# should remain what it was before (dry-run restores it).
mkfile "${SRC}/b.txt" "second"
run_sync -n "${SRC}" "${DST}"
assert_equal "${RUN_RC}" "0" || exit 1

assert_file_missing "${DST}/b.txt" || exit 1
after=$(cat "${SRC}/.m3sync/current-state")
assert_equal "${after}" "${before}" || exit 1
