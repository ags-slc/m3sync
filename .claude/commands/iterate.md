---
description: Run one autonomous improvement cycle on m3sync — pick the highest-priority open bug, write a regression test, apply the fix, verify, commit.
---

Run one improvement cycle on the m3sync codebase. The cycle is:

## 1. Pick a target

Read `/Users/ags/Projects/m3sync/docs/FINDINGS-bugs.md`. Identify the
highest-priority unresolved bug. Priority order:

1. Critical (data loss / correctness) — BUG-01 through BUG-04, BUG-33.
2. High (likely breakage in normal use) — BUG-05 through BUG-11.
3. Medium, then Low.

Skip bugs that are clearly out-of-scope right now (e.g., "rewrite to
POSIX-pure", "introduce vector clocks"). An out-of-scope bug stays in the
doc; don't delete it.

Check `git log --oneline` to see which bugs already have fixes committed.
A committed fix looks like `Fix BUG-NN: ...`. Skip already-fixed bugs.

If all in-scope bugs are fixed, switch to calling the `refactor-finisher`
agent to continue the partial functional refactor instead.

## 2. Write the regression test

Dispatch the `test-writer` sub-agent with the selected BUG-NN ID and the
relevant context from the findings doc. Wait for it to return. Verify:
- The new test file exists under `tests/`.
- Running `tests/run.sh <new-test>` fails in the expected way.

If the test passes unexpectedly against the unfixed code, the bug report
is wrong or the test is too weak. Stop and report.

## 3. Apply the fix

Edit `/Users/ags/Projects/m3sync/m3sync` to resolve the bug. Guidelines:
- Minimum change necessary. Don't reformat surrounding code.
- Match existing style (2- or 4-space indent as already used in the
  function, `typeset` declarations at function top, etc.).
- If the fix changes observable behavior (e.g., removes `-u` from base
  opts), add a line to the commit message flagging the behavior change.

Run `tests/run.sh`. All previously-passing tests must still pass; the new
regression test must now pass.

## 4. Review

Dispatch the `reviewer` sub-agent. If it returns `block` or
`request-changes`, address the findings and re-run the reviewer. Loop until
`approve` (max 3 iterations; if still blocked, stop and hand off).

## 5. Commit

```sh
git add m3sync tests/test_bugNN_*.sh
git commit -m "$(cat <<'EOF'
Fix BUG-NN: <short description>

<1-3 sentence explanation of the bug and the fix approach>

Regression test: tests/test_bugNN_<name>.sh
EOF
)"
```

Do **not** push. Do **not** amend an earlier commit. One bug per commit.

## 6. Report

End the iteration with a one-paragraph summary:
- Which bug was addressed.
- The commit SHA.
- Remaining pass/fail matrix.
- Suggested next target (so `/loop` can pick up where you left off).

## Stopping conditions

- No critical/high bugs remain AND the refactor-finisher reports "no obvious
  next step" → stop.
- Tests regress and you cannot resolve in-cycle → stop, surface the issue.
- Reviewer blocks three times → stop, surface the disagreement.
