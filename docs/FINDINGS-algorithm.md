# m3sync Algorithm Findings

Source: `/Users/ags/Projects/m3sync/m3sync` (464 lines, commit `a4b488e`).

## a) Formal model

Each endpoint keeps, under `.m3sync/`:

- `previous-state` / `current-state` — path-only `find` snapshots
- `last-run` — mtime = wallclock of last completed run
- `delta` — `diff(previous, current)` over *names* (modifications in place never appear)
- `protected-list` = `{.m3sync*}` ∪ names in delta ∪ `find -newer last-run`

One invocation, in pseudo-code:

```
lock(source)
S_prev := S_curr
S_curr := find(source)
D := diff(S_prev, S_curr)
P := {.m3sync*} ∪ names(D) ∪ newer(source, last-run)
if target_initialized:
    rsync -abCu --delete --exclude-from=P target → source     # leg 1
rsync -abCu --delete source → target                            # leg 2
touch last-run
unlock(source)
```

**There is no CRDT property.** No version vectors, no Lamport clocks, no causal
history, no tombstones, no per-file IDs. Reconciliation = **mtime last-write-wins
via `rsync -u`**, scoped by a one-sided protected-list that only affects the
inbound leg. The invariant the author relies on: "between runs, only one side
edited any given file."

Protection is only a **masking primitive for the inbound leg**; it is not
conflict resolution. Protected files' target-side versions are buried by the
outbound leg (moved into `backup/<ts>/` via `-b`).

Only the **source** runs `prepare_sync`. The target has no
`last-run`/`delta`/`protected-list` in use — protection is asymmetric.

## b) Scenario matrix

| # | Scenario | Outcome | Correct? |
|---|---|---|---|
| 1 | S modifies X | X is newer-than-last-run → protected on leg 1; leg 2 pushes S→T. | Yes |
| 2 | T modifies X | Not protected on S; leg 1 pulls T→S; leg 2 is a no-op (`-u`). | Yes |
| 3 | Both modify X | X protected on S; T's newer content **not pulled**; leg 2 overwrites T with S's content; T's edit ends up in `target/.m3sync/backup/<ts>/`. | **Silent loss.** No conflict marker; only recoverable from backup. |
| 4 | S deletes X, T untouched, still *within first cycle after delete* | X is in `delta` with `<` → name goes into protected-list, excluded on leg 1, and leg 2 `--delete` removes X on T. | Yes |
| 4′ | S deleted X *previous* cycle (already propagated); T later gains X again out-of-band | X is not in S's delta and not newer than last-run; leg 1 pulls X back to S. **Deletion resurrected with no warning.** | **Incorrect.** No tombstones across cycles. |
| 5 | T deletes X | `--delete` on leg 1 deletes X from S. | Yes |
| 6 | S modifies X, T deletes X | X is protected on S, leg 1 doesn't delete; leg 2 repushes X to T. | Arguable (data preserved). |
| 7 | S deletes X, T modifies X | X name is in protected-list (`<`); leg 1 doesn't pull T's modified X; leg 2 `--delete` removes X on T. **T's modification lost** (only in T's own backup dir). | **Silent loss.** |
| 8 | S renames X→Y | Treated as delete + create; full resend, no rename optimization. | Semantically OK, inefficient. |
| 9 | S creates X, T creates Y independently | Adds are commutative; both sides converge to {X, Y}. | Yes |
| 10 | First sync, target populated but uninitialized | `mode` stays `mirror`; `sync_protected` skipped; leg 2 runs `--delete` source→target. **Every pre-existing target file moved to `backup/<ts>/` and removed from live tree.** | **Destructive surprise.** Not documented. |
| 11 | Two syncs in same minute | `timestamp` is `+%Y%m%d%H%M`; `backup/<ts>/` and `changelog/<ts>/` collide; second run overwrites first's history entry. | Latent audit-trail corruption. |
| 12 | Third machine joins rotation | Works only if seeded empty or by copy. Each endpoint's `last-run` is local. Easy to hit scenario 10 or split-brain. No causal tracking. | Accident-prone. |

Additional findings:

- **Mode downgrade**: if `.m3sync/` on target is ever removed, next run silently degrades to unidirectional mirror (scenario 10). No guard.
- **Protection is one-sided**: whichever side initiates gets the protection window. Switching the initiator flips semantics.
- **Pattern gotcha**: `--exclude=.m3sync*` has no leading `/` — matches at any depth, so a user file named `.m3syncNOTES` anywhere is excluded.
- **Clock skew vs `-u`**: a target edit with skewed-backwards mtime can be silently rejected by `-u` on ingest *and then deleted* on the outbound leg. LWW+clock-skew is brutal.

## c) Failure modes

- **Interrupt between `sync_protected` and `sync`**: state already rotated, `last-run` not yet touched; inbound already applied. Next run: T-origin files are in `current-state` (won't be in delta) but still newer-than-last-run (still protected). Safe, slightly over-protective.
- **Interrupt between state rotation and any rsync**: next run's `previous-state` is from two runs ago; delta spans two windows; `last-run` unchanged ⇒ protection is broader. Safe (errs on the side of protection).
- **rsync fails mid-transfer**: `set -e` aborts; `trap … EXIT` releases lock. `last-run` not bumped and `changelog/<ts>/` not populated, so retry semantics are sound, but `current-state` has already been rotated into `previous-state`, so the next delta is computed against the post-attempt state. Acceptable.
- **Orphaned lock (SIGKILL)**: `mkdir` lock + trap-based release. Trap does not fire on SIGKILL. Lock persists indefinitely with no PID file, no staleness check. Must be removed manually.
- **`get_delta` + `set -e`**: `diff … || return 0` is load-bearing; if `previous-state` doesn't exist, function returns nothing and `cf_delta` is truncated to empty, which is the correct behavior (all names become "new" via the newer-than-last-run clause) but only by accident.

## d) vs. Syncthing / real CRDTs

| Feature | Syncthing | m3sync |
|---|---|---|
| Block-level deltas | yes (BEP rolling hash, persisted block index) | only inside a single rsync invocation; no persisted block index |
| Per-file version vectors | yes | none |
| Tombstones | yes, with expiry | none — enables deletion resurrection |
| Conflict detection | yes — `X.sync-conflict-<ts>-<device>.ext` | none — silent LWW, losers go to `backup/<ts>/` |
| Multi-device | full mesh | star with source-initiator; 3+ is accidental |
| Causality | device IDs + vector clocks | wallclock mtime + "did this side touch it since this side's last-run" |

**What m3sync gives you**: a mirror that survives edits on both sides *provided
edits don't overlap*, full `-a` fidelity, per-run backup directory (manual
recovery), a simple changelog, atomic `mkdir` lock, one file, no daemon.

**What it doesn't**: concurrency safety, deletion tracking across cycles,
conflict surfacing, rename detection, symmetric protection, causal correctness
for 3+ peers.

## e) Concrete scary scenarios

**A — Deletion resurrection.** User deletes `Receipts/2025/` on S in cycle N,
sync propagates deletion to T. In cycle N+1 the NAS admin restores
`Receipts/2025/` on T directly (outside m3sync). Cycle N+2: S's delta is empty,
nothing is newer than last-run, nothing is protected. Leg 1 pulls
`Receipts/2025/` back to S. The user's deliberate deletion is silently undone.

**B — Silent conflict loss.** Bob edits `notes.md` on S in the morning
(mtime=10:00). Alice edits `notes.md` on T (e.g. via NFS share of the target)
in the afternoon (mtime=14:00). Bob runs m3sync that evening from S.
`notes.md` is newer-than-last-run on S ⇒ protected. Leg 1 skips it (Alice's
14:00 content stays on T). Leg 2 pushes S's 10:00 content to T; Alice's 14:00
version is moved to `target/.m3sync/backup/<ts>/notes.md`. No warning, no
`.conflict` file, nothing in the log that flags this. If Alice doesn't know to
dig into `.m3sync/backup/`, her edits are effectively gone.

**C — Helpful-admin wipe.** Admin removes `.m3sync/` on the target ("cleaning
up weird dotdir"). Next run from S: `is_initialized(target)` returns false,
`mode` stays `mirror`, `sync_protected` skipped, leg 2 runs
`rsync -a --delete source → target`. Everything on T that is not on S is moved
aside and disappears from the live tree. `finalize_sync` happily re-initializes
the target afterwards. There is no refuse-to-run check.

## f) Algorithmic improvements (ranked cheap/high-value → expensive)

1. **Refuse-to-run on populated + uninitialized target** (trivial, high value).
   Before leg 2, check whether target has any non-hidden content and
   `.m3sync/` missing; if so, abort with `--force-initial-sync` required. Kills
   scenario 10/C.
2. **Conflict surfacing instead of silent LWW** (cheap, high value). Before the
   outbound leg, intersect `protected-list` with `find(target)`. Any overlap =
   both sides modified → `ssh target "mv X X.conflict-<ts>-<host>"` before leg
   2. Matches Syncthing convention. Kills scenario 3/B.
3. **Persistent tombstones** (cheap, high value). Keep the last N
   `previous-state`s (or a dedicated `known-set`); any name known-gone that
   later reappears on the peer is deleted on ingest (`--exclude` on leg 1 +
   `--delete` on leg 2). Kills scenario 4′/A.
4. **Second/nanosecond + PID in timestamp** (trivial, medium value).
   `date +%Y%m%d%H%M%S` plus `$$`. Kills scenario 11.
5. **Atomic two-phase completion marker** (trivial, medium value). Write
   `.m3sync/in-progress` before first rsync; remove after `touch last-run`. On
   startup, presence means previous run died mid-flight; choose broader
   protection / skip delta rotation.
6. **Stale-lock recovery** (trivial, low-medium value). Write PID + hostname
   into the lock; on collision, `kill -0` the PID and honour a `timeout`.
7. **Hashed state** (moderate, medium value). Augment `find` output with
   `cksum` (POSIX CRC-32). Modifications-in-place become visible from state
   alone, reducing reliance on `find -newer last-run` and on clock sanity.
8. **Symmetric protection** (moderate, high value). Run `prepare_sync` on the
   target too (over SSH); intersect protected sets. Protection stops being
   initiator-dependent. Combined with (2), this is a real bidirectional sync.
9. **Per-file version vectors** (high cost, high value). `(device_id, counter)`
   per path; merge by vector dominance; incomparable ⇒ conflict. The only path
   to principled 3+ device correctness (scenario 12).
