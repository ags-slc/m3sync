#!/bin/sh
# BUG-11: rsync -u in base_opts causes divergence when source is protected
# but target has a newer mtime. The protected-list model already says
# "source wins for locally-edited paths"; -u then sabotages the outbound
# leg by refusing to overwrite the target. Result: both sides keep their
# own version forever.

setup_env

# Establish shared baseline.
mkfile "${SRC}/foo.txt" "baseline"
run_sync
run_sync   # engages full-duplex

# Simulate a conflict: both sides edit foo after the last sync. Source's
# edit makes the file "newer than last-run" → protected during leg 1.
# Target's mtime is pushed further into the future so rsync -u would
# (incorrectly) skip the outbound push. We manipulate mtimes directly so
# the test doesn't need to sleep.
mkfile "${SRC}/foo.txt" "source-version"   # mtime = now; newer than last-run
mkfile "${DST}/foo.txt" "target-version"
touch_future "${DST}/foo.txt" 1000         # target mtime pushed +1000s

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# The protected-list model says source wins (it's in delta / newer than
# last-run on source, so protected during the inbound leg; outbound
# rsync then pushes source to target). With -u, target stayed at
# "target-version" (divergence). Without -u, target ends up at
# "source-version".
s=$(cat "${SRC}/foo.txt")
d=$(cat "${DST}/foo.txt")
if [ "${s}" != "${d}" ]; then
    fail "divergence: source='${s}' target='${d}'"
    exit 1
fi
assert_equal "${d}" "source-version" || exit 1
