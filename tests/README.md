# m3sync test suite

A small, dependency-light POSIX-shell test harness for `m3sync`. All tests run
against the local-path form of the target URI (no SSH), so they are safe for
CI.

## How to run

From the repo root:

```sh
# Run everything
tests/run.sh

# Run a single test (any of these forms work)
tests/run.sh test_usage
tests/run.sh test_usage.sh
tests/run.sh tests/test_usage.sh

# Verbose — echoes captured output for failing tests, and per-invocation
# exit codes from run_sync.
VERBOSE=1 tests/run.sh
```

Output is TAP-ish:

```
ok 1 - test_usage
not ok 2 - test_full_duplex_basic
1..10
# pass=… fail=… xfail=… xpass=…
```

A test file whose first 20 lines contain `# EXPECT_FAIL` is treated as an
expected failure: a nonzero exit is reported as `XFAIL` and does not fail the
suite; a zero exit is reported as `XPASS` and does fail the suite.

## What each test covers

| Test | Purpose |
| --- | --- |
| `test_usage.sh` | `m3sync -h` prints the usage banner and exits 0. |
| `test_no_args.sh` | Calling with no args prints the usage banner and exits 0. |
| `test_init_source.sh` | First run creates `.m3sync/` with `settings`, `last-run`, `backup/`, `changelog/`. |
| `test_one_way_sync.sh` | Source has files, target empty; after one sync the target holds the files. |
| `test_full_duplex_basic.sh` | Two-phase: initialize both sides, then a file that exists only on target gets pulled to source. |
| `test_full_duplex_delete_source.sh` | A file deleted on source is also deleted from target after the next sync. |
| `test_full_duplex_delete_target.sh` | A file deleted on target is propagated back to source when source is quiescent (older than `last-run`, not in delta). |
| `test_dry_run_no_state.sh` | `-n` does not mutate `.m3sync/current-state` and does not write to the target. |
| `test_lock_exclusion.sh` | A pre-existing `.m3sync/lock` rejects a second invocation and does not remove the lock. |
| `test_path_with_spaces.sh` | `EXPECT_FAIL`. File names containing spaces round-trip unchanged. |

## Conventions

- Each test is sourced by the runner inside a subshell with a fresh
  `$TESTDIR` (from `mktemp -d`). The runner `rm -rf`s the tmp dir afterward.
- Helpers live in `lib.sh`:
  - `setup_env` – create `$SRC` and `$DST` under `$TESTDIR`.
  - `run_sync [args...]` – invoke `$M3SYNC`; no args means
    `$M3SYNC "$SRC" "$DST"`. Captures `RUN_OUT` and `RUN_RC`.
  - `mkfile path content`, `touch_past path seconds_ago`,
    `touch_future path seconds_ahead`.
  - `assert_file_exists`, `assert_file_missing`,
    `assert_file_contents`, `assert_equal`, `assert_contains`, `fail`.
- Tests should early-exit on the first failed assertion
  (`assert_* || exit 1`).
- No bats-core, no fixtures on disk — everything is built up in the tmp dir.

## Initial pass/fail state

The suite intentionally captures real bugs in the current `m3sync`. The
results below are the expected state given a careful read of the script at
`m3sync`; tests marked "bug" surface defects the suite is meant to catch.

| Test | Status | Notes |
| --- | --- | --- |
| `test_usage.sh` | pass | `-h` path sets `mode=usage` and `echo "${help_text}"; exit`. |
| `test_no_args.sh` | pass | `"$#" -lt 2` triggers the same help branch. |
| `test_init_source.sh` | pass | `initialize_dir` creates the four expected entries and writes `settings`. |
| `test_one_way_sync.sh` | pass | With target uninitialized, only the push leg runs and writes files through. |
| `test_full_duplex_basic.sh` | pass (likely) | Aging source mtimes keeps the file off the protected list, so the pull leg delivers it. |
| `test_full_duplex_delete_source.sh` | pass | The deleted file appears in the source's delta, so `get_protected_list` excludes it from the pull; the push leg's `--delete` removes it from target. |
| `test_full_duplex_delete_target.sh` | pass (likely) | With source aged and quiescent, the pull leg's `--delete` removes the target-deleted file from source. |
| `test_dry_run_no_state.sh` | **fail — bug** | `prepare_sync` moves the old `current-state` to `previous-state` and writes a new one *before* the `-n` branch is evaluated. `cp current-state restore-state` then captures the new state, and `restore_current_state` just moves that same new state back. The net effect is that `current-state` reflects the dry-run snapshot instead of being restored to the pre-run snapshot. |
| `test_lock_exclusion.sh` | pass | `mkdir lock` fails, `log_msg error`, `exit 1`; the EXIT trap is set only after successful acquisition, so the pre-existing lock dir is untouched. |
| `test_path_with_spaces.sh` | **xfail — bug** | Multiple unquoted expansions (`${1}`, `${source_dir}`, `${target_dir}`) in `filtered_find`, `initialize_dir`, `prepare_sync`, `sync`, `sync_protected`, etc. word-split on spaces, so spaced paths either error out or sync the wrong files. |

### Bugs this suite points at

1. **Dry run leaks state** (`test_dry_run_no_state.sh`). `finalize_sync`'s
   `restore_current_state` restores a copy of the *new* current-state, not
   the previous one. A follow-up real sync would then see an empty delta and
   miss protecting files the user added during the dry run. The fix is to
   snapshot `previous-state` (or the pre-move `current-state`) into
   `restore-state`, not the post-move new current-state.
2. **No support for spaces (or shell metacharacters) in paths**
   (`test_path_with_spaces.sh`). The script consistently uses unquoted
   variable expansions, so any whitespace or glob character in `source_dir`,
   `target_dir`, or file names will misbehave. Fixing this requires
   systematically quoting expansions and, in a few places (e.g.
   `filtered_find`'s `grep -v ${cf_dir}`), switching to safer filters.

Other smaller issues spotted while authoring tests but not directly asserted:

- `get_backup_opts` computes a conditional `backup_opts` and then
  unconditionally overwrites it with `--backup-dir=${backup_path}` on the
  next line, so the local-vs-remote branch is dead code.
- `log_msg` references `${is_debug}` but the global is only set when `-d` is
  passed; under `set -u` this would be an unbound-variable error. The script
  does not use `set -u`, so it silently treats it as empty/zero.
- `filtered_find` uses `grep -v ${cf_dir}` (unquoted, unanchored), which can
  incorrectly filter any path containing the substring `.m3sync`.
