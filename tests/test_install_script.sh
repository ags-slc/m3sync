#!/bin/sh
# install.sh downloads m3sync from the configured URL base and drops it
# at $M3SYNC_PREFIX. This test points the installer at a local file://
# "repo" so it exercises the download path without hitting the network.

setup_env

# Skip when curl isn't available (the installer itself refuses too).
if ! command -v curl > /dev/null 2>&1; then
    echo SKIP
    exit 0
fi

# Fake repo layout matching raw.githubusercontent.com/OWNER/REPO/REF/FILE.
REPO="${TESTDIR}/fakerepo"
mkdir -p "${REPO}/testref"
cp "${M3SYNC_ROOT}/m3sync" "${REPO}/testref/m3sync"

PREFIX="${TESTDIR}/bin"
out=$(
    M3SYNC_URL_BASE="file://${REPO}" \
    M3SYNC_REF=testref \
    M3SYNC_PREFIX="${PREFIX}" \
    sh "${M3SYNC_ROOT}/install.sh" 2>&1
)
rc=$?
assert_equal "${rc}" "0" || { printf '%s\n' "${out}" >&2; exit 1; }

# The installed file must exist and be executable.
assert_file_exists "${PREFIX}/m3sync" || exit 1
[ -x "${PREFIX}/m3sync" ] || { fail "installed m3sync is not executable"; exit 1; }

# And it must actually run.
"${PREFIX}/m3sync" -h > /dev/null 2>&1 || { fail "installed m3sync -h failed"; exit 1; }

# Bad URL: download fails, no partial file left behind.
bad_prefix="${TESTDIR}/bin2"
M3SYNC_URL_BASE="file://${REPO}" \
    M3SYNC_REF=nonexistent-ref \
    M3SYNC_PREFIX="${bad_prefix}" \
    sh "${M3SYNC_ROOT}/install.sh" > /dev/null 2>&1
rc=$?
if [ "${rc}" -eq 0 ]; then
    fail "installer succeeded on a nonexistent ref; expected failure"
    exit 1
fi
assert_file_missing "${bad_prefix}/m3sync" || exit 1
assert_file_missing "${bad_prefix}/m3sync.tmp" || exit 1

# Non-shebang payload: refuse and leave no residue.
mkdir -p "${REPO}/bogusref"
printf 'just some text, not a script\n' > "${REPO}/bogusref/m3sync"
bogus_prefix="${TESTDIR}/bin3"
M3SYNC_URL_BASE="file://${REPO}" \
    M3SYNC_REF=bogusref \
    M3SYNC_PREFIX="${bogus_prefix}" \
    sh "${M3SYNC_ROOT}/install.sh" > /dev/null 2>&1
rc=$?
if [ "${rc}" -eq 0 ]; then
    fail "installer accepted non-shebang payload"
    exit 1
fi
assert_file_missing "${bogus_prefix}/m3sync" || exit 1
assert_file_missing "${bogus_prefix}/m3sync.tmp" || exit 1
