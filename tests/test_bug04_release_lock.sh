#!/bin/sh
# BUG-04: release_lock did `rm -rf "${active_lock_dir}" && log || log`,
# which (a) is a footgun if active_lock_dir is empty ("rm -rf \"\"" is a
# no-op today but a maintenance hazard), and (b) silently swallows
# failures via the &&/|| chain. Verify that a successful sync removes
# the lock dir and that a second sync can acquire it cleanly.

setup_env

mkfile "${SRC}/a.txt" "a"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_missing "${SRC}/.m3sync/lock" || exit 1

# Second run must also succeed and not find a stale lock.
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_missing "${SRC}/.m3sync/lock" || exit 1
