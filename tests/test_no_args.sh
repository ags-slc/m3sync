#!/bin/sh
# With no args, m3sync prints usage (and exits without erroring the runner).

setup_env
# Invoke with zero args — bypass run_sync's default source/target.
RUN_OUT=$("${M3SYNC}" 2>&1); RUN_RC=$?

assert_equal "${RUN_RC}" "0" || exit 1
assert_contains "${RUN_OUT}" "Usage:" || exit 1
