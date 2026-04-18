#!/bin/sh
# Filenames containing spaces must sync correctly. This was historically
# broken by filtered_find's unquoted ${root} expansion; BUG-06/BUG-34's
# rewrite fixes it. Locks in the fix.

setup_env
mkfile "${SRC}/hello world.txt" "spaced"

run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists   "${DST}/hello world.txt"          || exit 1
assert_file_contents "${DST}/hello world.txt" "spaced" || exit 1
