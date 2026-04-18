#!/bin/sh
# With no args (missing required source_dir and target_uri), m3sync
# prints usage and exits 2 (sysexits EX_USAGE). BUG-24.

setup_env
# Invoke with zero args — bypass run_sync's default source/target.
RUN_OUT=$("${M3SYNC}" 2>&1); RUN_RC=$?

assert_equal "${RUN_RC}" "2" || exit 1
assert_contains "${RUN_OUT}" "Usage:" || exit 1
