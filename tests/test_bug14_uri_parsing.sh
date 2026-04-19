#!/bin/sh
# BUG-14: parse_sync_params used 'IFS=":"; set ${target_uri}', which
# splits on EVERY colon and mis-handles: (a) local paths that happen to
# contain a colon, (b) IPv6 targets in 'user@[ipv6]:path' form,
# (c) rsync:// URLs. Fix: split on the first colon only, recognize the
# IPv6 bracket form, refuse rsync:// explicitly.

setup_env

# (a) A local path containing a colon must be treated as local.
mkfile "${SRC}/greet.txt" "hello"
DST_COLON="${TESTDIR}/dir:with:colons"
mkdir -p "${DST_COLON}"
run_sync "${SRC}" "${DST_COLON}"
assert_equal "${RUN_RC}" "0" || exit 1
assert_file_exists "${DST_COLON}/greet.txt" || exit 1

# (b) rsync:// URLs are not yet supported; m3sync must refuse them
# with a clear error rather than splitting on the colons.
RUN_OUT=$("${M3SYNC}" "${SRC}" "rsync://host/module" 2>&1)
RUN_RC=$?
if [ "${RUN_RC}" -eq 0 ]; then
    fail "rsync:// URL was accepted (rc=0); expected refusal"
    exit 1
fi
case "${RUN_OUT}" in
    *rsync://*) : ;;
    *) fail "rsync:// refusal did not mention the URL scheme: ${RUN_OUT}"; exit 1 ;;
esac

# (c) IPv6 bracket form. Install an ssh shim that records the host arg;
# m3sync should pass the whole bracketed host through unsplit.
mkdir -p "${TESTDIR}/bin"
cat > "${TESTDIR}/bin/ssh" <<'SHIM'
#!/bin/sh
# Only record the FIRST ssh invocation; later calls from other sync
# phases (conflict detection, tombstone purge) can shift the perceived
# host and would race. Skip leading flags to find the host arg.
if [ ! -s "${SHIM_LOG}" ]; then
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -[a-zA-Z]) shift ;;
            -[a-zA-Z]=*) shift ;;
            --) shift; break ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    printf '%s\n' "$1" > "${SHIM_LOG}"
fi
exit 1
SHIM
chmod +x "${TESTDIR}/bin/ssh"
export SHIM_LOG="${TESTDIR}/ssh-host.log"
PATH="${TESTDIR}/bin:${PATH}"
export PATH

# Pre-initialize another source so is_initialized(target_dir) — which
# invokes ssh — runs.
SRC6="${TESTDIR}/src6"
mkdir -p "${SRC6}/.m3sync/backup" "${SRC6}/.m3sync/changelog"
touch "${SRC6}/.m3sync/last-run"
mkfile "${SRC6}/bait.txt" "hi"

"${M3SYNC}" "${SRC6}" 'user@[::1]:/tmp/path' > /dev/null 2>&1 || true
[ -f "${SHIM_LOG}" ] || fail "ssh shim was never invoked for IPv6 target"
got=$(cat "${SHIM_LOG}")
assert_equal "${got}" 'user@[::1]' || exit 1
