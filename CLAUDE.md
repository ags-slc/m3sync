# m3sync — project instructions for Claude

`m3sync` is a single-file POSIX-ish shell script wrapping `rsync` to do
bi-directional, non-concurrent file sync with minimal dependencies. It was
started as a thought experiment and used in production for a while. See
`README.md`, `docs/ARCHITECTURE.md`, and `docs/USAGE.md` for end-user facing
context.

## Ground rules

1. **Preserve the ethos.** The tool is valued for being one script, no
   dependencies beyond POSIX + rsync + (optionally) ssh. Do not introduce
   Python, Perl, Node, SQLite, or any runtime dependency. `awk`, `sed`,
   `find`, `diff`, `sort`, `cksum`, `sha256sum`/`shasum`, `stat` are fair
   game.
2. **Every bug fix ships with a regression test.** Add a `tests/test_*.sh`
   reproducing the bug before fixing it. If a test already covers the case,
   note the test name in the commit message.
3. **Run the full suite after any code change** (`tests/run.sh`). Expect the
   `XFAIL`-marked tests to stay xfail until explicitly resolved.
4. **Commit incrementally.** One fix, one commit. Use imperative-mood
   subject lines ("Fix X" not "Fixing X"). Reference the BUG-NN ID from
   `docs/FINDINGS-bugs.md` where applicable.
5. **Don't invent semantic changes.** If a proposed fix changes observable
   behavior (e.g., remove `-u` / `-C` from base opts), surface the tradeoff
   in the commit message and leave the decision to the human if uncertain.
6. **Respect the partial refactor.** The script was mid-refactor toward a
   more functional style (pure functions returning values via `echo`,
   orchestration only in `main`). Continue in that direction; do not
   regress toward global-mutation style.

## Known environmental gotchas

- macOS 13+ ships `openrsync` as `/usr/bin/rsync`. It is **not** feature
  compatible with GNU rsync — notably, `-b --backup-dir` + `--delete`
  silently drops deletions (BUG-33). m3sync auto-detects openrsync at
  startup (`detect_openrsync` / `is_openrsync`) and degrades gracefully by
  dropping `-b`. Everything else works under openrsync, including the
  test suite. **No `brew install rsync` is required** — it just restores
  the backup safety net for users who want it.

## Key files

- `m3sync` — the script.
- `install.sh` — the curl-installer. Honors `M3SYNC_PREFIX`,
  `M3SYNC_REF`, `M3SYNC_URL_BASE`.
- `tests/run.sh` — test runner; each `test_*.sh` is independent. Use
  `VERBOSE=1` for trace output.
- `tests/lib.sh` — helpers (`setup_env`, `run_sync`, `mkfile`,
  `assert_file_{exists,missing}`, `touch_past`, `touch_future`).
- `.shellcheckrc` — project lint config. Run `shellcheck -s bash m3sync`
  and `shellcheck -s sh tests/*.sh install.sh` before committing; CI
  enforces this. The file documents which specific SC codes are
  project-wide disabled and why; everything else should be fixed at
  the call site or carry an inline `# shellcheck disable=` with a
  comment justifying it.
- `.github/workflows/ci.yml` — CI runs shellcheck on every push/PR,
  plus the test suite on Ubuntu (GNU rsync) and macOS (openrsync).
- `docs/FINDINGS-bugs.md` — numbered bug list (BUG-01…BUG-33). Authoritative.
- `docs/FINDINGS-algorithm.md` — sync-semantics analysis + scenario matrix.
- `docs/FINDINGS-concurrency.md` — Syncthing-style concurrency design
  (phased plan if we ever decide to ship vector clocks).
- `docs/ARCHITECTURE.md`, `docs/USAGE.md`, `docs/CONTRIBUTING.md` — user docs.

## Sub-agents available

See `.claude/agents/`:

- `bug-hunter` — finds and files new bugs; does not fix.
- `test-writer` — writes regression tests from a bug ID or scenario description.
- `refactor-finisher` — continues the partial functional refactor; no
  behavior change.
- `shell-quality` — enforces clean shell code + wide POSIX compatibility;
  can apply minimal behavior-preserving cleanups.
- `reviewer` — reviews a diff before commit; catches regressions and
  style drift.

Use them via `Agent(subagent_type: "<name>", ...)`. Prefer sub-agents for
parallel exploration and for protecting the main context from large tool
outputs.

## Autonomous iteration

`.claude/commands/iterate.md` is a slash command that runs one iteration
cycle: pick the highest-priority open bug from `FINDINGS-bugs.md`, dispatch
`test-writer` to add a regression test, verify the test fails, apply the
fix, verify the test passes, run the full suite, commit. Invoke with
`/iterate` or combine with `/loop` for unattended runs.

## Out of scope right now

- The full Phase-A→D concurrency refactor in `docs/FINDINGS-concurrency.md`.
  That is a major rewrite and should only happen when the maintainer signs
  off. Small steps toward it (e.g., device-id file + diagnostic warning) are
  OK if explicitly asked.
