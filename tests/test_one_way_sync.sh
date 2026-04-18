#!/bin/sh
# Source has files, target empty: after sync target gets the files.

setup_env
mkfile "${SRC}/a.txt"        "alpha"
mkfile "${SRC}/sub/b.txt"    "bravo"

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

assert_file_exists    "${DST}/a.txt"         || exit 1
assert_file_contents  "${DST}/a.txt" "alpha" || exit 1
assert_file_exists    "${DST}/sub/b.txt"     || exit 1
assert_file_contents  "${DST}/sub/b.txt" "bravo" || exit 1
