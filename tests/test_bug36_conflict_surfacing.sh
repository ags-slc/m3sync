#!/bin/sh
# BUG-36: when both sides modify the same file between runs, the
# protected-list model makes source win at the canonical path (per
# BUG-11), but the target's losing version was moved into
# .m3sync/backup/<ts>/ where users don't look. Instead, preserve the
# loser as a visible sibling with Syncthing-style
# <base>.sync-conflict-<YYYYMMDD>-<HHMMSS>-<host><ext>.

setup_env

# Baseline shared between source and target.
mkfile "${SRC}/foo.txt" "baseline"
mkfile "${SRC}/README"  "base-noext"
run_sync
run_sync   # engage full-duplex

# Concurrent edits on both sides.
mkfile "${SRC}/foo.txt" "source-edit"
mkfile "${DST}/foo.txt" "target-edit"
touch_future "${DST}/foo.txt" 1000

mkfile "${SRC}/README" "source-readme"
mkfile "${DST}/README" "target-readme"
touch_future "${DST}/README" 1000

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# Source wins at canonical paths on both sides.
assert_file_contents "${DST}/foo.txt" "source-edit"   || exit 1
assert_file_contents "${SRC}/foo.txt" "source-edit"   || exit 1
assert_file_contents "${DST}/README"  "source-readme" || exit 1

# Target has a sync-conflict sibling for each, containing the loser.
c1=$(ls "${DST}"/foo.sync-conflict-*.txt 2>/dev/null | head -n 1)
[ -n "${c1}" ] || fail "no sync-conflict sibling for foo.txt on target"
assert_file_contents "${c1}" "target-edit" || exit 1

c2=$(ls "${DST}"/README.sync-conflict-* 2>/dev/null | head -n 1)
[ -n "${c2}" ] || fail "no sync-conflict sibling for README on target"
assert_file_contents "${c2}" "target-readme" || exit 1

# Source also got the conflict sibling (copied from target before rename).
s1=$(ls "${SRC}"/foo.sync-conflict-*.txt 2>/dev/null | head -n 1)
[ -n "${s1}" ] || fail "no sync-conflict sibling for foo.txt on source"
assert_file_contents "${s1}" "target-edit" || exit 1
