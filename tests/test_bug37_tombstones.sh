#!/bin/sh
# BUG-37: when a path is deleted on source and that deletion propagates
# to target in cycle N, an out-of-band restore on target (admin, backup,
# sneakernet) in cycle N+1 would cause cycle N+2's leg 1 to silently
# pull the file back to source — the user's deliberate deletion undone
# with no signal. Persistent tombstones close this.

setup_env

# Baseline shared between source and target.
mkfile "${SRC}/doc.txt" "important"
# A second file so BUG-02's empty-source guard doesn't fire when we
# delete doc.txt below.
mkfile "${SRC}/keeper.txt" "always"
run_sync
run_sync   # engage full-duplex

# Cycle N: delete on source, sync propagates to target.
rm "${SRC}/doc.txt"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_missing "${SRC}/doc.txt" || exit 1
assert_file_missing "${DST}/doc.txt" || exit 1

# Tombstone file must now contain doc.txt.
[ -f "${SRC}/.m3sync/tombstones" ] || fail "tombstones file not created"
grep -q '^doc\.txt	' "${SRC}/.m3sync/tombstones" \
    || fail "doc.txt missing from tombstones file"

# Out-of-band resurrection on target.
mkfile "${DST}/doc.txt" "resurrected-by-admin"

# Cycle N+2: the resurrection must NOT propagate to source. Instead,
# the tombstone triggers deletion of the resurrected file on target.
run_sync
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_missing "${SRC}/doc.txt" || exit 1
assert_file_missing "${DST}/doc.txt" || exit 1

# If the user intentionally re-creates the file on source, the
# tombstone should clear and normal sync should resume.
mkfile "${SRC}/doc.txt" "new-era"
run_sync
assert_file_contents "${SRC}/doc.txt" "new-era" || exit 1
assert_file_contents "${DST}/doc.txt" "new-era" || exit 1

if grep -q '^doc\.txt	' "${SRC}/.m3sync/tombstones" 2>/dev/null; then
    fail "doc.txt still in tombstones after explicit re-add"
    exit 1
fi
