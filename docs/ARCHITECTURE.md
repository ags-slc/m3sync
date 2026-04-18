# Architecture

This document describes how `m3sync` models synchronization, what it keeps on
disk, and the order in which it does things. It is aimed at readers who want
to understand, audit, or modify the tool. All line references are to the
`m3sync` script at the repository root.

## Model

`m3sync` is a thin orchestrator around two back-to-back `rsync` invocations.
The core idea:

1. Before copying anything, record a listing of every file and directory
   under the source.
2. Compare that listing to the previous run's listing to derive a set of
   entries that have been added, removed, or touched on the source since
   last time.
3. Treat that set as a "protected list" -- things the source just changed,
   which should not be clobbered by a pull from the target.
4. If both sides have `.m3sync/` state (full-duplex mode), pull from target
   to source first, excluding the protected list. This picks up target-only
   changes.
5. Push from source to target. `rsync -u` prevents newer target files from
   being overwritten by older source copies, so this step is safe to run
   unconditionally.
6. Record the run: move the delta and previous-state into a timestamped
   `changelog/` subdirectory, touch `last-run`, release the lock.

Conflicts are resolved by modification time via `rsync -u` (last-write-wins).
There is no merge.

## Control directory layout

Every synced tree gets a `.m3sync/` directory at its root on first run
(`initialize_dir`, line 177). Inside it:

| Path | Written by | Contains |
| --- | --- | --- |
| `settings` | `initialize_dir` (line 187); user | Space-separated `key value` lines. Currently understood keys are `enabled` and `mode`. Read by `set_overrides` (line 138) only when `-o` is given. |
| `last-run` | `finalize_sync` (line 407); `initialize_dir` (line 188) | Empty file whose mtime marks the last successful sync. Used by `get_protected_list` to find entries modified since the last run. |
| `previous-state` | `prepare_sync` (line 319) | The file listing from the prior run, used as the left-hand side of the next `diff`. Moved into `changelog/<timestamp>/` at the end of each run. |
| `current-state` | `prepare_sync` (line 322) | The file listing for this run, produced by `filtered_find`. |
| `restore-state` | `prepare_sync` (line 328) | Copy of `current-state` taken only for dry runs. Restored over `current-state` during `finalize_sync` so the next real run sees the correct baseline. |
| `delta` | `prepare_sync` (line 323) | Output of `diff previous-state current-state`. Lines beginning with `<` or `>` are the adds/removes used to build the protected list. |
| `protected-list` | `prepare_sync` (line 324) | Newline-delimited, sort-unique list of paths that the target-to-source pull must not touch. Consumed by `rsync --exclude-from` in `sync_protected`. |
| `backup/<timestamp>/` | `rsync --backup --backup-dir=...` | Files that `rsync` replaced or deleted on this run. The receiving side of each `rsync` call gets its own timestamped backup directory. |
| `changelog/<timestamp>/` | `record_history` (line 352) | Per-run snapshot containing the `previous-state` listing and the `delta` for that run. This is the audit trail. |
| `lock/` | `get_lock` (line 203) | Mutex. Created with `mkdir` (atomic), removed by the `EXIT` trap (`release_lock`, line 196). Presence means a sync is in progress or crashed. |

The timestamp used throughout is `date '+%Y%m%d%H%M'` -- minute precision
(line 35). Two runs started in the same minute on the same side will collide
on `backup/` and `changelog/` paths.

## Full-duplex vs one-way

`m3sync` chooses its mode in `main` (lines 439-445):

- If the source has no `.m3sync/`, the script initializes it and proceeds
  in `mirror` mode: source pushes to target, no pull.
- If the source has `.m3sync/` but the target does not, the script proceeds
  in `mirror` mode and initializes the target during `finalize_sync`
  (line 402).
- If both sides have `.m3sync/`, `mode` is set to `full-duplex` and the
  target-to-source pull (`sync_protected`) is performed before the push.

In other words: the first run from each side bootstraps state; every run
after that is bi-directional.

Full-duplex is detected by calling `is_initialized` (line 162), which runs
`stat .m3sync` locally on the source and either locally or over `ssh` for
the target depending on whether the target URI contains a host component.

## Algorithm, step by step

Entry point is `main` (line 411). The sequence for an enabled sync:

1. **Parse options** with `getopts` (lines 413-423).
2. **Parse the source and target** (`parse_sync_params`, line 112). The
   target URI is split on `:` into optional host and directory.
3. **Apply settings overrides** if `-o` was passed (`set_overrides`, line
   138).
4. **Check initialization** and pick `mirror` vs `full-duplex`
   (lines 440-445).
5. **Acquire the lock** (`get_lock`, line 203). Installs an `EXIT` trap to
   release it on any exit path.
6. **Prepare sync state** (`prepare_sync`, line 308):
   - Rotate `current-state` -> `previous-state`.
   - Build a fresh `current-state` via `filtered_find` (line 223). This
     walks the source with `find`, keeps files, directories, and symlinks,
     strips the source prefix, and excludes `.m3sync/`.
   - Compute `delta` by diffing the two state files.
   - Build `protected-list` (`get_protected_list`, line 259):
     - Always include `.m3sync*`.
     - Include everything in the delta (lines starting with `<` or `>`).
     - Include everything under the source that is newer than `last-run`.
   - Assemble `rsync_opts`: `--timeout=15 --delete -abCu --exclude=.m3sync*`
     plus `n` for dry run or `v` for verbose.
7. **Pull protected** (`sync_protected`, line 340), only in full-duplex
   mode. Runs `rsync ... --exclude-from=protected-list target_uri/
   source_dir`. This brings target-only changes into the source without
   touching anything the source has locally modified.
8. **Push** (`sync`, line 380). Runs `rsync ... source_dir/ target_uri`.
   `-u` means newer target files are skipped, preserving target-only edits
   that were already pulled down.
9. **Finalize** (`finalize_sync`, line 392):
   - On dry run: restore `current-state` from `restore-state` so state is
     unchanged.
   - Otherwise: initialize the target if necessary, call `record_history`
     to move `previous-state` and `delta` into `changelog/<timestamp>/`,
     and `touch last-run`.
10. **Release the lock** via the `EXIT` trap.

## Data flow

```
   source_dir                                       target_uri
   ----------                                       ----------
       |                                                |
       | 1. scan: find -> current-state                 |
       | 2. diff previous-state current-state -> delta  |
       | 3. protected-list = .m3sync* + delta adds/rm   |
       |                     + newer-than last-run      |
       |                                                |
       |       [full-duplex only]                       |
       |   <---- rsync --exclude-from protected --------|   sync_protected
       |         -abCu --delete --backup-dir=...        |
       |                                                |
       |   ---- rsync -abCu --delete ------->           |   sync
       |         --exclude=.m3sync*                     |
       |         --backup-dir=...                       |
       |                                                |
       | 4. mv previous-state, delta -> changelog/TS/   |
       | 5. touch last-run                              |
       | 6. rmdir lock/                                 |
```

The `-u` flag on both invocations is what makes full-duplex safe: a file
that the target-to-source pull just dropped into place with a newer mtime
will not be overwritten by the subsequent source-to-target push.

## Conflict resolution

Conflict resolution is whatever `rsync -u` does: skip the transfer if the
destination file has a modification time newer than or equal to the source.
Consequences:

- Edits on both sides between runs: the side with the newer mtime wins, the
  other is overwritten. The overwritten copy is preserved in the receiving
  side's `backup/<timestamp>/` directory (because of `-b`).
- Clock skew between hosts can flip the winner. Use `ntpd` or equivalent.
- A `touch` on either side is enough to win a conflict without actually
  changing content.

There is no prompt, no `.conflict` file, and no manual merge step.

## Backups and recovery

Because `rsync` is invoked with `-b --backup-dir=<timestamped-path>`, every
file that `rsync` replaces or deletes is preserved under `.m3sync/backup/`
on the receiving side of that transfer. In a full-duplex run the source can
accumulate backups from the pull phase, and the target accumulates backups
from the push phase.

To recover a file:

```sh
# List backup runs on the source.
ls .m3sync/backup/

# Find your file within a specific run.
find .m3sync/backup/202604181542 -name 'notes.md'

# Copy it back into place.
cp .m3sync/backup/202604181542/notes.md ./notes.md
```

Backups are never pruned automatically. Delete old `backup/<timestamp>/`
directories manually when you are confident you do not need them.

The `changelog/` tree is separate from backups. It holds the `previous-state`
listing and the `delta` diff for each run, which is useful for answering
"what did the script think had changed on this run?" but is not a data
backup.

## Locking

`get_lock` uses `mkdir .m3sync/lock` as an atomic lock primitive. If the
directory already exists, `mkdir` fails and the script exits without
running. On any exit path, the `EXIT` trap runs `release_lock`, which
removes the directory.

If a run is killed hard (SIGKILL, power loss) the lock directory is left
behind and subsequent runs will refuse to start. The fix is manual:

```sh
rmdir .m3sync/lock
```

The lock is per source-side invocation. It does not coordinate across
hosts; two machines syncing against each other at the same instant will
both acquire their own local locks and run concurrently. This is one of
the "non-concurrent" constraints in the README.
