#!/bin/sh
# BUG-09: set_overrides ends the read loop with '|| return 0', which was
# intended to "tolerate missing keys" but actually only suppresses I/O
# errors (unreadable config). Missing keys are already tolerated by the
# case fallthrough. Confirm the script does NOT silently swallow an
# unreadable settings file — the read should either surface or, at the
# very least, not mask downstream behavior.

setup_env

# Establish source + first sync so the settings file exists.
mkfile "${SRC}/a.txt" "hello"
run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# Make settings unreadable and invoke with -o (override from settings).
chmod 000 "${SRC}/.m3sync/settings"

# With -o, a read error on settings must not silently "succeed". Accept
# either a nonzero exit or a log mentioning the file; the current bug is
# that both are absent.
RUN_OUT=$("${M3SYNC}" -o -v "${SRC}" "${DST}" 2>&1)
RUN_RC=$?

# Restore perms so cleanup works.
chmod 644 "${SRC}/.m3sync/settings"

if [ "${RUN_RC}" -eq 0 ]; then
    fail "unreadable settings was swallowed silently (rc=0); set_overrides must surface I/O errors"
    exit 1
fi
