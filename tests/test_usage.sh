#!/bin/sh
# m3sync -h prints usage and exits 0.

setup_env
run_sync -h

assert_equal "${RUN_RC}" "0" || exit 1
assert_contains "${RUN_OUT}" "Usage:" || exit 1
assert_contains "${RUN_OUT}" "source_dir" || exit 1
