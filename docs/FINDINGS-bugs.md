# Bug findings

`shellcheck` was not available; findings below are from manual review of
`/Users/ags/Projects/m3sync/m3sync`.

## Critical (data loss / correctness)

- **[BUG-37] Deletion resurrection: peer-side restore silently undoes an intentional delete** — m3sync:sync_protected (pre-fix)
  - What: scenario A from `docs/FINDINGS-algorithm.md`. Source deletes X in cycle N, the deletion propagates to target. Between cycles, X reappears on target (admin restore, backup restore, sneakernet). Cycle N+1's delta is empty; the path is neither in the delta nor newer-than-last-run, so it's not protected. Leg 1 (target → source, `--exclude-from=protected-list`) happily pulls X back to source. The user's deliberate deletion is silently undone.
  - Impact: cumulative data-correctness drift. Deletions are not durable across resurrection events.
  - Suggested fix: persist a `.m3sync/tombstones` file listing every path that has been deleted on source, with epoch timestamps. On each run, purge any tombstoned path that has reappeared on target (local `rm` or ssh `rm`), and clear any tombstone whose path has been deliberately re-created on source. Prune entries older than `M3SYNC_TOMBSTONE_DAYS` (default 30) so the file doesn't grow unbounded.

- **[BUG-36] Conflicts silently buried in `.m3sync/backup/<ts>/`** — m3sync:sync (pre-fix)
  - What: when both sides modify the same path between runs, the protected-list picks source as the winner, and the target's losing version gets moved into `.m3sync/backup/<ts>/` by rsync's `-b` (when using GNU rsync) or simply overwritten (openrsync, per BUG-33). Users had no visible signal that a conflict happened. By the time they noticed the divergence days later, the backup directory was buried under unrelated runs and often never checked.
  - Impact: Syncthing-style silent data loss. Exactly scenario B in `docs/FINDINGS-algorithm.md`.
  - Suggested fix: before the outbound rsync, intersect the protected-list with "files the target has with different content" (`cksum` comparison), and for each hit rename the target's version to `<stem>.sync-conflict-<YYYYMMDD>-<HHMMSS>-<host><ext>` (Syncthing convention). Mirror the conflict sibling back to the source so both sides see the loss. Works under both GNU rsync and openrsync because the rename happens out-of-band — not via `-b`.

- **[BUG-35] Dry-run leaves mutated state files on disk** — m3sync:393 (pre-fix)
  - What: `prepare_sync` rotated `current-state` into `previous-state`, wrote the new scan as `current-state`, then (for dry-run) `cp current-state → restore-state`. `finalize_sync`'s dry-run path then `mv restore-state → current-state` — which restored the *new* state over itself. The "restore" was a no-op; every dry-run permanently advanced the state machine one step.
  - Impact: a user running `m3sync -n` intending to preview a change saw `b.txt` absent from target (good) but `b.txt` appeared in `current-state` on disk (bad). Next non-dry-run's delta would then miss the change.
  - Suggested fix: reverse the rotation in `restore_current_state`: move `previous-state` back to `current-state` and delete the ephemeral `delta`/`protected-list` files. Exercised by `tests/test_dry_run_no_state.sh`.

- **[BUG-34] `filtered_find` pipeline exits 1 when no user files match, aborting the script under `set -e`** — m3sync:235
  - What: `find ... | sed ... | grep -v X | grep -v Y`. On an empty source tree (or one where the only content is inside `.m3sync/`), `grep -v` sees no lines matching anything, exits 1, and since the pipeline's exit code is the last command's, the whole pipeline exits 1. `get_current_state`'s only statement is `filtered_find`, so it returns 1. The caller is `get_current_state ${1} > ${1}/${cf_current_state}`. Under `set -e`, the script aborts before `get_delta` / `get_protected_list` / `sync_protected` / `sync` can run.
  - Impact: if the user deletes the last file from the source, running m3sync silently dies mid-flight. The target keeps all its files forever, with no deletion propagating, and no error surfaced to the user (`set -e` exits 0-ishly from the top level with the lock released).
  - Repro:
    ```sh
    T=$(mktemp -d); mkdir -p "$T/s" "$T/d"
    echo one > "$T/s/only.txt"; ./m3sync "$T/s" "$T/d"; ./m3sync "$T/s" "$T/d"
    rm "$T/s/only.txt"; ./m3sync -dv "$T/s" "$T/d"
    ls "$T/d"        # only.txt still there
    ```
  - Suggested fix: two independent fixes both helpful. (a) Make `filtered_find` tolerant of empty pipelines: `grep -v ... || true` on the last grep, or replace both `grep -v` with a single `awk '!/pattern/'` that returns 0 on empty. (b) Better: replace the double-grep with a path-scoped `find` predicate (`find "${1}" -not -path '*/.m3sync*' \( -type f -o -type d -o -type l \)`) — simultaneously fixes BUG-06 (`notes-m3sync.txt` false-positive) and BUG-34.

- **[BUG-33] openrsync on macOS silently drops `--delete` when `-b --backup-dir` is also passed** — environmental, affects m3sync:314
  - What: macOS 13+ ships `openrsync` (BSD-licensed replacement) as `/usr/bin/rsync` — the banner reads `openrsync: protocol version 29 / rsync version 2.6.9 compatible`. With `rsync -ab --delete --backup-dir=<dir>`, openrsync does **not** delete extraneous files on the destination and does **not** populate the backup dir. `rsync -a --delete` alone works correctly.
  - Impact: all delete-propagation on macOS-to-macOS and anything-to-macOS is broken. This is the root cause of `tests/test_full_duplex_delete_source` and `tests/test_full_duplex_delete_target` failing on the author's machine. Repro in 8 lines:
    ```sh
    T=$(mktemp -d); mkdir -p "$T/src" "$T/dst"
    echo k > "$T/src/keep.txt"; echo g > "$T/dst/gone.txt"
    rsync -ab --delete --backup-dir=".bak/ts" "$T/src/" "$T/dst/"
    ls "$T/dst"   # openrsync: keep.txt gone.txt   GNU rsync: keep.txt
    ```
  - Fix applied: `detect_openrsync` at startup sets `is_openrsync=1` when the banner matches. `base_opts` drops `-b` and `get_backup_path` returns empty under openrsync, so deletions propagate correctly. Openrsync remains supported as a first-class environment — `brew install rsync` is **not** required, it merely restores the per-run backup dir. Long-term follow-up: CI matrix with both GNU rsync and openrsync.

- **[BUG-01] `get_backup_opts` always ignores the branch it just computed** — m3sync:285-306
  - What: The function picks between local (`${1}/${backup_path}`) and remote (`${backup_path}`) `--backup-dir` based on whether the receiver is remote, assigning `backup_opts` inside each branch. Then line 302 unconditionally overwrites: `backup_opts="--backup-dir=${backup_path}"` (no receiver prefix).
  - Why it's wrong: The if/else at 296-300 is dead code. For local sync the intended form `--backup-dir=/abs/path/.m3sync/backup/<ts>` is never produced; the relative path happens to work because rsync resolves `--backup-dir` relative to destination root, but any future fix to either branch is silently erased. `backup_opts` declared as module-level global at line 72 is also never used.
  - Suggested fix: Delete line 302; delete the dead global on line 72.

- **[BUG-02] `sync --delete` nukes target when source is empty-but-initialized** — m3sync:389
  - What: If `.m3sync` survives but the source tree is emptied, `is_initialized` returns true, full-duplex engages, `sync_protected` copies nothing (empty protected list), then `sync` runs source→target with `--delete` and wipes the target. `-u` only gates transferred files not deletions.
  - Repro: Sync two non-empty dirs; `rm -rf source_dir/*` (leave `.m3sync`); `m3sync source target`; target wiped.
  - Suggested fix: Add `--max-delete=<N>` or refuse when current-state is empty but previous-state is not.

- **[BUG-03] Command injection via `ssh ${target_host} "${cmd}"`** — m3sync:168-174, 177-191
  - What: `is_initialized` builds `cmd="stat ${1}/${cf_dir}"` then runs `ssh ${target_host} "${cmd}"`. `${1}` is `target_dir` from argv (split only on `:`). Spaces, `;`, `$(...)`, backticks are re-interpreted by the remote shell. `initialize_dir` line 190 has the same issue.
  - Repro: `m3sync ./src 'host:/tmp/$(touch /tmp/pwned)'`.
  - Suggested fix: Pass path as argument: `ssh "${target_host}" sh -c 'stat "$0/.m3sync"' "${1}"`; quote `${target_host}`.

- **[BUG-04] `release_lock` silent-fails** — m3sync:196-201
  - What: `rm -rf "${active_lock_dir}" && log || log`. `active_lock_dir` defaults to empty (line 66). `rm -rf ""` is today a no-op but remains a footgun. The `&& || ` pattern swallows failures — the trap exits 0 while the lock dir persists; next run is wedged with no staleness detection.
  - Suggested fix: Use `rmdir` (dir-only, fails loudly); guard with `[ -n "${active_lock_dir}" ]`; add pid/mtime staleness check.

## High (likely breakage in normal use)

- **[BUG-05] `timestamp` minute precision → collisions clobber backups & history** — m3sync:35, used at 291, 359
  - `timestamp=$(date '+%Y%m%d%H%M')`. Two runs in the same minute overwrite the first's history and backup artifacts.
  - Suggested fix: `+%Y%m%d%H%M%S` minimum; `+%Y%m%d%H%M%S.$$` for safety.

- **[BUG-06] `grep -v ${1}` and `grep -v ${cf_dir}` in `filtered_find` are wrong** — m3sync:235
  - `find $@ \( ${file_types} \) | sed ${pattern} | grep -v ${1} | grep -v ${cf_dir}` — (a) all expansions unquoted, break on spaces; (b) `grep -v ${1}` is regex, over-matches on metachars; (c) `grep -v ${cf_dir}` matches `.m3sync` as substring anywhere, so a file named `notes-m3sync.txt` is dropped from current-state, never protected, could be deleted on next duplex cycle.
  - Suggested fix: `find "${1}" ... -not -path '*/.m3sync*'`; drop both greps; quote expansions.

- **[BUG-07] `is_debug` referenced but never declared** — m3sync:101, 416
  - `[[ "${is_debug}" -eq 0 ]]` works today because `[[ "" -eq 0 ]]` treats empty as 0 — but this breaks the moment `set -u` is added and any typo like `is_dbg=1` is silently accepted.
  - Suggested fix: Add `typeset -i is_debug=0` at line 42.

- **[BUG-08] `set_overrides` trusts config file contents without validation** — m3sync:149-157
  - `mode ${2}` accepts any string; no whitelist.
  - Suggested fix: Whitelist valid values per key in the case arms.

- **[BUG-09] `done < "${config_file}" || return 0` masks real errors** — m3sync:158
  - Comment says "config may not have all settings" but `while read` through EOF always returns 0 regardless. The `|| return 0` silently swallows I/O errors.
  - Suggested fix: Remove `|| return 0`.

- **[BUG-10] `rsync -C` (cvsignore) in base opts is a surprising default** — m3sync:314
  - `-C` auto-excludes `.git/`, `CVS/`, `*.o`, `*~`, `#*#`, `.svn/`, plus in-tree `.cvsignore`. A general-purpose sync tool silently dropping `.git/` is astonishing.
  - Suggested fix: Drop `-C` from base opts; gate behind the existing `-c` flag.

- **[BUG-11] `rsync -u` (update) contradicts the protected-list model** — m3sync:314
  - `-u` skips files newer on receiver. Design uses protected-list for conflict resolution; `-u` layers mtime-based resolution on top. `--delete` is not subject to `-u`, so a newer-on-receiver file can still be deleted if absent from sender — asymmetric.
  - Suggested fix: Remove `-u`; trust protected-list.

## Medium (edge cases, portability)

- **[BUG-12] Shebang `/usr/bin/env sh` but script uses ksh/bash features** — m3sync:1
  - What: `typeset -r`, `typeset -i`, `[[ ... ]]`, `local -r` are not POSIX. On dash (Ubuntu's `/bin/sh`), the script died on line 33: `typeset: not found`, taking every test with it at rc=127.
  - Fix applied: shebang changed to `#!/usr/bin/env bash` and the header comment now states bash (or a sufficiently ksh-compatible shell) as the runtime dependency. A pure-POSIX rewrite remains out of scope — the feature surface we'd lose (typed integers, `[[ ]]`, `local`) is not worth the readability cost for this script. Surfaced by CI, which is exactly why we set CI up.

- **[BUG-13] `typeset -r timestamp=...` prevents re-derivation** — m3sync:35
  - Readonly prevents retry logic from refreshing the timestamp; compounds BUG-05.

- **[BUG-14] `parse_sync_params` splits URI naively** — m3sync:120-135
  - `IFS=":"; set ${target_uri}` — paths containing `:` lose data; `rsync://` and IPv6 forms unsupported; `$# -gt 2` silently truncates.

- **[BUG-15] `grep "[<|>]" | colrm 1 2` is a lossy diff parser** — m3sync:255, 271
  - `colrm 1 2` strips two leading chars unconditionally; breaks if diff emits anything other than `< ` / `> ` prefixes, and filenames containing `<`, `>`, `|` pollute the match.
  - Suggested fix: `comm -3` on sorted inputs, or `diff --line-format` flags.

- **[BUG-16] `filtered_find` contract is implicit — `$1` is both find root and sed/grep operand** — m3sync:223-236
  - A future arg reorder silently corrupts output.

- **[BUG-17] `get_lock`'s `mkdir` is non-`-p`; ordering assumptions implicit** — m3sync:211

- **[BUG-18] `initialize_dir` remote branch doesn't `touch last-run`** — m3sync:186-191

- **[BUG-19] `sync_cvsignore` clobbers remote `~/.cvsignore` every `-c` run** — m3sync:369-378

## Low (style, clarity)

- **[BUG-20] `local -r msg="$@"` in scalar context** — m3sync:98. Use `"$*"`.
- **[BUG-21] `echo` used for data instead of `printf`** — m3sync:108, 184, 269, 305, 428.
- **[BUG-22] Unquoted expansions pervasive** — 171, 187, 235, 244, 253, 255, 278, 322-324, 347, 349, 386, 389, 400, 403, 406-407, 436, 440-442, 450-451, 454, 457-458.
- **[BUG-23] Trailing whitespace on lines 424, 434.**
- **[BUG-24] `exit` with no code after usage** — m3sync:429. Invalid flag path exits 0.
- **[BUG-25] Arithmetic `-eq` on 0/1 flags** — m3sync:101, 106, 326, 331, 388, 399, 435, 439.
- **[BUG-26] `is_initialized` uses `stat`** — m3sync:168. `[ -d "${1}/${cf_dir}" ]` is cheaper, portable, clearer.
- **[BUG-27] `sync` is passed an unused second arg** — m3sync:457.
- **[BUG-28] Success-path "lock released" notice is noisy** — m3sync:199.
- **[BUG-29] No preflight check for `rsync`/`ssh` binaries.**
- **[BUG-30] `help_text` interpolates `${cf_settings}` at definition time.**
- **[BUG-31] `restore_current_state` has no doc comment** — m3sync:281-283.
- **[BUG-32] `log_msg debug "... $@"` inside double quotes inconsistent with `msg="$@"`** — m3sync:98, 233.
