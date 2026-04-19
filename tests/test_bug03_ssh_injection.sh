#!/bin/sh
# BUG-03: m3sync interpolates target_dir (and target_host) into ssh
# command strings. A URI like 'host:/tmp/$(touch /tmp/pwned)' would get
# its $(...) evaluated by the remote shell. Fix: refuse target paths
# containing shell metacharacters at parse time, before the value ever
# reaches ssh.

setup_env

mkfile "${SRC}/a.txt" "bait"

# Install an ssh shim that records every invocation. If validation works,
# ssh is never called for these malicious URIs; the log stays empty.
mkdir -p "${TESTDIR}/bin"
cat > "${TESTDIR}/bin/ssh" <<'SHIM'
#!/bin/sh
printf '%s\n' "[shim] called" >> "${SHIM_LOG}"
SHIM
chmod +x "${TESTDIR}/bin/ssh"
export SHIM_LOG="${TESTDIR}/shim.log"
: > "${SHIM_LOG}"
PATH="${TESTDIR}/bin:${PATH}"
export PATH

_check_unsafe_rejected() {
    uri=$1
    MARKER="${TESTDIR}/pwned"
    rm -f "${MARKER}"
    run_sync "${SRC}" "${uri}"
    if [ "${RUN_RC}" -eq 0 ]; then
        fail "m3sync accepted unsafe URI '${uri}' (rc=0)"
        return 1
    fi
    assert_file_missing "${MARKER}" || return 1
    if [ -s "${SHIM_LOG}" ]; then
        fail "ssh shim was invoked for unsafe URI '${uri}':
$(cat "${SHIM_LOG}")"
        : > "${SHIM_LOG}"
        return 1
    fi
    return 0
}

# Each of these should be refused at parse time.
MARKER="${TESTDIR}/pwned"
# The $(touch ...) must NOT expand locally; single quotes around it
# are the point of the test. shellcheck's SC2016 correctly notes the
# non-expansion, which is exactly what we want here.
# shellcheck disable=SC2016
_check_unsafe_rejected 'fakehost:/tmp/safe-$(touch '"${MARKER}"')-dir' || exit 1
_check_unsafe_rejected 'fakehost:/tmp/safe-`touch '"${MARKER}"'`-dir'  || exit 1
_check_unsafe_rejected 'fakehost:/tmp/foo;touch\ '"${MARKER}"           || exit 1
_check_unsafe_rejected 'fakehost:/tmp/a|b'                              || exit 1

# Positive control: a benign local target should still work (no ssh
# involved, so the shim log stays empty regardless).
run_sync "${SRC}" "${DST}"
assert_equal "${RUN_RC}" "0" || exit 1
