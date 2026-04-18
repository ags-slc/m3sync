#!/bin/sh
# BUG-05: timestamp uses minute precision (%Y%m%d%H%M), so two or more
# syncs in the same minute collide: the second run's changelog/<ts>/
# entry overwrites the first. Audit-trail corruption.

setup_env

# Three distinct runs in quick succession; each run makes a content change
# so that a new previous-state is archived to changelog/<ts>/ on the next
# run.
mkfile "${SRC}/a.txt" "one"
run_sync
mkfile "${SRC}/a.txt" "two"
run_sync
mkfile "${SRC}/a.txt" "three"
run_sync

# Expect at least two distinct changelog entries (the second and third
# runs each archive the previous-state). With minute-precision they
# collide into one; with second-or-better precision they are distinct.
count=$(ls "${SRC}/.m3sync/changelog/" 2>/dev/null | wc -l | tr -d ' ')
[ "${count}" -ge 2 ] || fail "expected >=2 changelog entries, got ${count} (BUG-05 timestamp collision)"
