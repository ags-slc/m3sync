#!/bin/sh
# BUG-15: get_protected_list used `grep "[<|>]"` to pick change lines out
# of a plain-diff, then `colrm 1 2` to strip the prefix. The character
# class was loose (included '|') and unanchored. Tightened to `^[<>] `
# so the parser only accepts lines with the literal 2-char diff prefix.
# This test exercises the protected-list flow on filenames that contain
# '|', '<', '>' — characters the old regex could have misclassified.

setup_env

# Names include pipe, lt, gt. These are legal on POSIX filesystems.
mkfile "${SRC}/a|b.txt" "pipe"
mkfile "${SRC}/c<d.txt" "lt"
mkfile "${SRC}/e>f.txt" "gt"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists "${DST}/a|b.txt" || exit 1
assert_file_exists "${DST}/c<d.txt" || exit 1
assert_file_exists "${DST}/e>f.txt" || exit 1

# Second cycle (full-duplex). Modify one of the oddly-named files on
# the source so it lands in the delta and therefore the protected-list.
# The tightened regex must still emit it via `^[<>] ` so the receive
# leg excludes it and the push leg carries the update.
mkfile "${SRC}/a|b.txt" "pipe-updated"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_contents "${DST}/a|b.txt" "pipe-updated" || exit 1
