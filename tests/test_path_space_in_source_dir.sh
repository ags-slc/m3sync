#!/bin/sh
# EXPECT_FAIL: BUG-22 — the main() / parse_sync_params path passes
# ${source_dir} and ${target_uri} unquoted into sub-commands and rsync,
# so a space in the source path is word-split. Filenames with spaces
# now work (see test_path_with_spaces.sh) because filtered_find was
# rewritten with a quoted ${root}; the rest of the script still needs
# its expansions tightened.

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
