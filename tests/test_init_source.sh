#!/bin/sh
# First run initializes .m3sync/ in the source with expected layout.

setup_env
mkfile "${SRC}/hello.txt" "hi"

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

assert_file_exists "${SRC}/.m3sync"           || exit 1
assert_file_exists "${SRC}/.m3sync/settings"  || exit 1
assert_file_exists "${SRC}/.m3sync/last-run"  || exit 1
assert_file_exists "${SRC}/.m3sync/backup"    || exit 1
assert_file_exists "${SRC}/.m3sync/changelog" || exit 1

# settings should record enabled state.
assert_contains "$(cat "${SRC}/.m3sync/settings")" "enabled" || exit 1
