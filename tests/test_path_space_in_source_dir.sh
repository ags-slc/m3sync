#!/bin/sh
# BUG-22: main() and parse_sync_params used to pass ${source_dir} and
# ${target_uri} unquoted to sub-commands and rsync, so a space in the
# source-dir or target-dir path would word-split and break the sync.
# The unquoted-expansion sweep quoted every path call site; this test
# locks in that paths containing spaces — both in filenames and in
# the containing directory itself — now sync end to end.

# Custom SRC/DST with a space in the path.
SRC="${TESTDIR}/has space/src"
DST="${TESTDIR}/has space/dst"
mkdir -p "${SRC}" "${DST}"
export SRC DST

mkfile "${SRC}/file.txt" "content"

run_sync "${SRC}" "${DST}"
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists "${DST}/file.txt" || exit 1
assert_file_contents "${DST}/file.txt" "content" || exit 1
