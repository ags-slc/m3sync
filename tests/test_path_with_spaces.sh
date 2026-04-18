#!/bin/sh
# EXPECT_FAIL: the script uses unquoted expansions (e.g. in filtered_find,
# is_initialized, initialize_dir, get_protected_list, and rsync invocations),
# so paths containing spaces are expected to break word-splitting and cause
# either a crash, a wrong sync, or a missing file on the target.

setup_env
mkfile "${SRC}/hello world.txt" "spaced"

run_sync
# Either the script exits nonzero, or the file won't appear correctly on the
# target. Any of these should cause the assertions below to fail.
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists   "${DST}/hello world.txt"          || exit 1
assert_file_contents "${DST}/hello world.txt" "spaced" || exit 1
