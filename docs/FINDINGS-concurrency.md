# Concurrency feasibility: Syncthing-style semantics

Can `m3sync` be extended to support true concurrent modification
(Syncthing-style), while preserving its "only rsync + POSIX utilities" ethos?

**Short answer:** Yes, in principle — with the understanding that
"concurrent-safe" here means "detects and preserves concurrent edits via
conflict files", not "operational-transform merges". The cost is roughly a
doubling of script size (464 → ~780 LOC) and the introduction of a persistent
per-file metadata index.

## 1. How Syncthing actually achieves concurrency

### 1.1 Per-device identity

Each Syncthing daemon generates a long-term ECDSA keypair on first launch.
The **device ID** is a base32 encoding of a truncated SHA-256 of the DER public
key (with a checksum). It is stable for the life of the keypair, globally
unique with overwhelming probability, and doubles as the TLS certificate
identity for BEP. Only two properties matter here: it is fixed per device, and
two devices can compare IDs without a trusted authority.

### 1.2 Block Exchange Protocol (BEP)

BEP is a TLS-framed message protocol. The two message types that carry
concurrency semantics:

- `ClusterConfig` — at connection setup, each side advertises folders,
  devices, and introductions.
- `Index` / `IndexUpdate` — a stream of `FileInfo` records describing the
  current state of each file in a folder.

A `FileInfo` record contains: `name`, `type`, `modified` (sec+ns), `size`,
`permissions`, `deleted` flag, `version` (vector clock), and `blocks` — an
array of `{offset, size, weak_hash, strong_hash}` at block granularity
(default 128 KiB, scaled by file size). The block list is the moral equivalent
of rsync's rolling-hash delta, precomputed once and gossiped.

### 1.3 Vector clocks per file

The `version` field is a set of `(deviceID -> counter)` pairs, encoded as a
list sorted by device ID. Syncthing bumps its own counter every time it
observes a new local version of a file. Given two versions `V1` and `V2`:

- `V1 == V2`: identical.
- `V1 <= V2` (every entry in V1 is <= the corresponding in V2, strictly less
  somewhere): V2 dominates — pull V2.
- `V2 <= V1`: mirror case — push V1.
- Otherwise: **concurrent**. Genuine conflict.

On concurrent detection, Syncthing keeps the winner by deterministic tiebreak
(typically higher mtime, then higher device ID) at the canonical path, and
renames the loser.

### 1.4 Tombstones

A delete is not absence of a `FileInfo`; it is a `FileInfo` with
`deleted=true` and a bumped version vector. Essential: lets us distinguish "A
deleted and B concurrently modified" from "B hasn't heard about the delete".
Retained until every known peer has acknowledged, then prunable.

### 1.5 Global vs. local state

Each device has a local DB with two views: local state (what exists on disk)
and global state (best version of every file across all peers, computed by
merging each peer's advertised index). The sync loop picks files where
global != local and pulls (if global dominates) or emits a conflict.

### 1.6 Conflict files

```
<basename>.sync-conflict-<YYYYMMDD>-<HHMMSS>-<SHORTID>.<ext>
```

`SHORTID` = first chars of the losing device ID. Conflict files are themselves
synced and have their own version vector, so users can merge manually and the
resolved version overwrites the canonical name.

### 1.7 Skimmed

Ignore patterns (`.stignore`), device introductions via a trusted introducer,
temp files written as `.syncthing.<name>.tmp` then atomically renamed.

## 2. What m3sync would need

### 2.1 Device ID

**Storage**: `.m3sync/device-id`, single line, created once.

```sh
generate_device_id() {
    if command -v uuidgen > /dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-16
    elif [ -r /dev/urandom ]; then
        head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        printf '%s' "$(hostname)$$$(date +%s)" | cksum | awk '{print $1}'
    fi
}
```

16 hex chars = 64 bits of entropy. `od -An -tx1` is fully POSIX. `uuidgen` is
near-universal. The fallback chain covers busybox/dash minimal environments.
The file must be preserved in backups — regenerating it breaks sync.

### 2.2 Per-file version vectors

**Recommendation: single TSV index file `.m3sync/index`.**

Rejected alternatives: sidecar-per-file (O(N) extra inodes, defeats rsync's
list handling); xattrs (not portable to FAT/exFAT, many NFS/SMB mounts, and
stripped by rsync unless `-X`); SQLite (breaks the POSIX-only ethos).

**Row format**:

```
path<TAB>version<TAB>mtime<TAB>size<TAB>hash<TAB>flags
```

Concrete examples:

```
notes/todo.md	a1b2c3d4e5f60718:3,c0ffee1234567890:1	1744988401	482	9f86d08188	ok
images/logo.png	a1b2c3d4e5f60718:1	1744980000	12844	3b0c44298f	ok
archive/old.log	a1b2c3d4e5f60718:2,c0ffee1234567890:4	1744900000	0	-	deleted
```

Rules: `path` is relative, tabs/newlines escaped. `version` is comma-sep
`<id>:<n>` sorted by id for canonical form. `mtime` is epoch seconds
(portability wrapper: `stat -c %Y` on GNU, `stat -f %m` on BSD). `hash` is
SHA-256 truncated to 16 hex chars (`-` for tombstones and dirs). `flags` ∈
{`ok`, `deleted`, `dir`, `symlink`}. Sorting by path makes `join`-based set
ops cheap.

### 2.3 Vector-clock operations

**Compare** (`vc_cmp`) → `eq|lt|gt|cc`:

```awk
function vc_cmp(v1, v2,    a, b, i, k, kv, le, ge) {
    split(v1, p1, ","); for (i in p1) { split(p1[i], kv, ":"); a[kv[1]] = kv[2]+0 }
    split(v2, p2, ","); for (i in p2) { split(p2[i], kv, ":"); b[kv[1]] = kv[2]+0 }
    le = 1; ge = 1
    for (k in a) if ((a[k]+0) > (b[k]+0)) le = 0
    for (k in b) if ((b[k]+0) > (a[k]+0)) ge = 0
    if (le && ge) return "eq"
    if (le)       return "lt"
    if (ge)       return "gt"
    return "cc"
}
```

**Merge** (elementwise max, sort via piped `sort -t: -k1,1` since POSIX awk
lacks `asort`):

```awk
function vc_merge(v1, v2,    m, i, k, kv) {
    split(v1, p1, ","); for (i in p1) { split(p1[i], kv, ":"); m[kv[1]] = kv[2]+0 }
    split(v2, p2, ","); for (i in p2) {
        split(p2[i], kv, ":")
        if (!(kv[1] in m) || (kv[2]+0) > m[kv[1]]) m[kv[1]] = kv[2]+0
    }
    for (k in m) print k ":" m[k]   # caller pipes through: sort -t: -k1,1 | paste -sd, -
}
```

**Bump** — called only on local modification:

```sh
vc_bump() {
    local existing="$1" me="$2"
    printf '%s\n' "$existing" | tr ',' '\n' | awk -F: -v me="$me" '
        BEGIN { found = 0 }
        $1 == me { printf("%s:%d\n", $1, $2+1); found = 1; next }
        NF     { print }
        END    { if (!found) printf("%s:1\n", me) }
    ' | sort -t: -k1,1 | paste -sd, -
}
```

Example: `vc_cmp "a1b2:3,c0ff:1" "a1b2:3,c0ff:2"` → `lt`.
`vc_cmp "a1b2:3,c0ff:1" "a1b2:2,c0ff:2"` → `cc`.

### 2.4 Block-level deltas

**We do not need to implement BEP blocks.** rsync already computes rolling-hash
deltas on the wire for every single-file transfer. We lose only multi-peer
parallel block pull, which is irrelevant for a pairwise tool. The architecture
becomes: (1) scan → `index.local`; (2) fetch `index.remote`; (3) `awk`-join
the two into `pull.list`, `push.list`, `conflict.list`, `delete.list`;
(4) drive `rsync --files-from=<list>` per phase. rsync handles per-file block
efficiency for free.

### 2.5 Tombstones

`flags=deleted`, `size=0`, `hash=-`, and a version vector dominating the
last-known live version.

- Remote `deleted`, local live, `local.v <= remote.v`: delete locally.
- Remote `deleted`, local live, concurrent: keep local as `.sync-conflict-*`,
  accept tombstone at canonical path.
- Both `deleted`, comparable: merge vectors.

**Retention**: drop tombstones older than `tombstone_retention_days` (default
30) that are dominated by every known peer's vector. For the pairwise case
this collapses to "both sides have merged and N days have passed".

### 2.6 Conflict files

```
<basename>.sync-conflict-<YYYYMMDD>-<HHMMSS>-<SHORTID><ext>
```

`SHORTID` = `cut -c1-6` of the losing device ID.

**Deterministic tiebreak**: higher `mtime` wins; on tie, lexicographically
greater device ID wins. Both machines compute the same winner from the same
index rows, so both rename the same file to the conflict name — convergence
without coordination.

### 2.7 Transport

Still rsync. Phases:

```sh
# 1. Exchange indices.
rsync -a peer:.m3sync/index     .m3sync/index.remote
rsync -a    .m3sync/index    peer:.m3sync/index.local

# 2. Decide (pure awk, no network).
derive_worklists .m3sync/index .m3sync/index.remote

# 3. Execute.
rsync -a --files-from=.m3sync/pull.list peer:folder/ folder/
rsync -a --files-from=.m3sync/push.list folder/      peer:folder/
apply_conflicts .m3sync/conflict.list
apply_deletes   .m3sync/delete.list

# 4. Merge and write-back.
merge_indices .m3sync/index .m3sync/index.remote > .m3sync/index.new
mv .m3sync/index.new .m3sync/index
rsync -a .m3sync/index peer:.m3sync/index
```

Every phase is idempotent against a crashed prior run, provided the index is
written last.

## 3. Minimum viable concurrent m3sync (MVC-m3sync)

### Phase A — metadata foundation (no behavioral change)

**Goal**: device IDs, index file, vector clocks, but keep "one writer at a
time". Index is written but does not yet gate rsync.

- **Files touched**: `m3sync`.
- **New state**: `.m3sync/device-id`, `.m3sync/index`.
- **New functions**: `ensure_device_id`, `scan_and_index`, `read_index`,
  `write_index`, `vc_cmp`, `vc_merge`, `vc_bump`.
- **Replaced**: `get_current_state` → `scan_and_index` (still emits the
  current-state list for backcompat).
- **Wrapped (unchanged)**: `prepare_sync`, `sync`, `sync_protected`.
- **LOC**: +120.
- **Validation**: two runs without edits leave every vector as `<me>:N`, N
  bumps only on real changes.

### Phase B — true concurrent modification

**Goal**: derive pull/push/conflict/delete lists from vector comparison;
retire mtime-LWW.

- **Files touched**: `m3sync` (possibly split awk helpers into `.m3sync/lib/`
  if >800 LOC).
- **New state**: `.m3sync/index.remote`,
  `.m3sync/{pull,push,conflict,delete}.list` (all transient).
- **New functions**: `fetch_remote_index`, `derive_worklists`,
  `apply_conflicts`, `apply_deletes`, `merge_indices`.
- **Replaced**: `sync_protected` → `apply_pull`; `sync` → `apply_push`;
  `get_delta` and `get_protected_list` become obsolete.
- **Wrapped**: `get_lock`, `record_history` (now logs work lists),
  `finalize_sync` (also writes merged index).
- **LOC**: +200 on top of A. Total ~780.
- **Validation**: fixture with two local dirs, mutate each, run, assert
  `.sync-conflict-*` present on both sides.

### Phase C — N-device support (N > 2)

**Goal**: same folder across 3+ devices.

- Vector model already supports this; harden merge to preserve transitively
  learned entries (don't drop unknown device IDs from received vectors).
- Manual admin command: `m3sync forget-device <id>` for pruning long-offline
  devices (automatic pruning requires quorum we don't have).
- New `.m3sync/peers` file; `m3sync` with no target iterates peers pairwise,
  sequentially.
- **New functions**: `forget_device`, `iter_peers`.
- **Replaced**: `parse_sync_params` accepts 0-arg form.
- **LOC**: +80.
- **Limitation**: convergence in N-device mesh bounded by connectivity graph
  of pairwise runs. Acceptable for cron-driven use.

### Phase D — tombstones, ignores, resumption

- `tombstone_retention_days` setting; prune in `finalize_sync` after
  dominance check.
- `.m3sync/ignore` (rsync-syntax patterns, not synced by default), applied in
  `scan_and_index` and as `--exclude-from`.
- `rsync --partial --partial-dir=.m3sync/partial` for resumption; stale
  partial dir triggers work-list regeneration.
- **LOC**: +60.

**Totals**: A+B gets real concurrent safety in ~780 LOC (up from 464). Add
C+D for ~900-950.

## 4. What we lose

### 4.1 Complexity

Today: 464 LOC, one mental model ("find + diff + rsync"). Post-B: ~780 LOC,
an awk library for vector arithmetic, a persistent index whose corruption can
silently resurrect deleted files. The index is now a database. Zero new
runtime deps, but it crosses from "weekend read" to "weekend project to reason
about". It is no longer a "thought experiment in 500 lines of sh"; it becomes
one in 800, still dwarfed by Syncthing's ~100 KLOC of Go — but the triviality
claim is gone.

### 4.2 Performance

Today's `find | diff` is O(N) stats + O(N) text diff. The proposal adds
SHA-256 per touched file (O(bytes-touched); hot path dominated by stat on
changed files only), index read/write (O(N) rows), awk comparison (O(N)). On
a 10k-file 1GB tree, cold index build is a few seconds of hashing; subsequent
runs are O(changed). Slower than today's mtime-only check on unchanged trees
but same order of magnitude. Much faster than `rsync --checksum`.

**Optimization**: cache `(mtime, size) -> hash` in the index, re-hash only
when `(mtime, size)` changes. Syncthing does exactly this.

### 4.3 Portability

- POSIX awk has everything we need: associative arrays, `split`,
  `for (k in a)`. Avoid: `asort`/`asorti`, `gensub`, `length(arr)`,
  `PROCINFO`. Sorting via external `sort`.
- Hashing: `shasum -a 256` (macOS), `sha256sum` (GNU),
  `openssl dgst -sha256` (universal fallback). Small dispatcher.
- `stat`: `stat -c %Y` (GNU) vs `stat -f %m` (BSD). Same dispatcher pattern.
- `find -printf` is GNU-only — avoid; use POSIX `find` + per-entry `stat`.
- ksh-only features (`typeset -r`, `[[ ]]`, `local`) are already required
  today; no new axis.

### 4.4 Clock skew

**Major win.** Today, `rsync -u` is mtime-LWW: a laptop five minutes behind
editing "after" a server edit silently loses. Vector clocks are indifferent
to wall time — mtime survives only in the cosmetic conflict-file name and the
tombstone retention cutoff (N days, not seconds). Multi-hour skew does not
affect convergence or conflict detection. This is a user-visible improvement
over today.

## 5. Recommendation

Worth doing, with caveats. The inflection point is Phase A → Phase B
(+120 → +320 LOC); the rest is polish. Phase A alone has standalone value:
shipping the index lets future runs *detect* "both sides touched this path
since last sync" and emit a warning, a direct fix for the README's documented
minute-precision and LWW footguns — even without yet *resolving* the conflict.

**Smallest-first-step (single PR)**: introduce `.m3sync/device-id` and an
append-only local `.m3sync/index`, without changing transfer behavior. Add
`ensure_device_id`, `scan_and_index`, and index read/write helpers; wire
`scan_and_index` into `prepare_sync`. Do **not** yet fetch the remote index,
derive work lists, or change rsync invocations. Add a diagnostic `-i` flag
that prints a "concurrent-edit warning" whenever a path's vector has been
bumped on both sides since last sync, to validate the mechanics in the field
before letting them drive deletions. ~120 LOC, breaks nothing, is necessary
substrate for every later phase, and if the maintainer stops here they still
shipped a real improvement: clock-skew-immune concurrent-edit *detection*,
without having lost the tool's small-script character.
