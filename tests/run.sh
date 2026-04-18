#!/bin/sh
# m3sync test runner. Discovers tests/test_*.sh, runs each in isolation, and
# prints TAP-like output. Exits nonzero if any non-xfail test fails.
#
# Usage:
#   tests/run.sh                 # run all tests
#   tests/run.sh test_usage      # run one test (name or filename)
#   VERBOSE=1 tests/run.sh       # echo all command output

set -u

# Locate ourselves — this file lives in <repo>/tests/.
TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
M3SYNC_ROOT=$(cd "${TESTS_DIR}/.." && pwd)
export M3SYNC_ROOT

# Build the list of tests to run.
if [ "$#" -gt 0 ]; then
    tests=""
    for arg in "$@"; do
        case "${arg}" in
            /*) f="${arg}" ;;
            tests/*) f="${M3SYNC_ROOT}/${arg}" ;;
            test_*) f="${TESTS_DIR}/${arg}" ;;
            *) f="${TESTS_DIR}/test_${arg}" ;;
        esac
        case "${f}" in
            *.sh) : ;;
            *) f="${f}.sh" ;;
        esac
        if [ ! -f "${f}" ]; then
            echo "runner: no such test: ${arg}" >&2
            exit 2
        fi
        tests="${tests} ${f}"
    done
else
    tests=$(ls "${TESTS_DIR}"/test_*.sh 2>/dev/null | sort)
fi

pass=0
fail=0
xfail=0
xpass=0
n=0
failed_names=""

for t in ${tests}; do
    n=$((n + 1))
    name=$(basename "${t}" .sh)

    # Each test gets its own tmpdir; runner cleans up.
    tdir=$(mktemp -d)

    # Read the first 20 lines for an EXPECT_FAIL marker — lets a test opt in
    # to being an expected failure without changing runner invocation.
    expect_fail=0
    if head -n 20 "${t}" 2>/dev/null | grep -q '^# EXPECT_FAIL'; then
        expect_fail=1
    fi

    # Run in a subshell so no state leaks between tests.
    out=$(
        TESTDIR="${tdir}"
        export TESTDIR
        # shellcheck disable=SC1090
        . "${TESTS_DIR}/lib.sh"
        # shellcheck disable=SC1090
        . "${t}"
    ) 2>&1
    rc=$?

    rm -rf "${tdir}"

    if [ "${expect_fail}" -eq 1 ]; then
        if [ "${rc}" -eq 0 ]; then
            xpass=$((xpass + 1))
            printf 'not ok %d - %s # XPASS (expected fail, but passed)\n' "${n}" "${name}"
            failed_names="${failed_names} ${name}"
        else
            xfail=$((xfail + 1))
            printf 'ok %d - %s # XFAIL\n' "${n}" "${name}"
        fi
    else
        if [ "${rc}" -eq 0 ]; then
            pass=$((pass + 1))
            printf 'ok %d - %s\n' "${n}" "${name}"
        else
            fail=$((fail + 1))
            failed_names="${failed_names} ${name}"
            printf 'not ok %d - %s\n' "${n}" "${name}"
            if [ "${VERBOSE:-0}" = "1" ]; then
                printf '%s\n' "${out}" | sed 's/^/    /'
            fi
        fi
    fi
done

echo "1..${n}"
printf '# pass=%d fail=%d xfail=%d xpass=%d\n' "${pass}" "${fail}" "${xfail}" "${xpass}"
if [ -n "${failed_names}" ]; then
    printf '# failing:%s\n' "${failed_names}"
fi

# Exit nonzero on real failures or unexpected passes.
if [ "${fail}" -gt 0 ] || [ "${xpass}" -gt 0 ]; then
    exit 1
fi
exit 0
