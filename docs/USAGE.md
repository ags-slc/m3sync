# Usage

Worked examples and reference material for day-to-day `m3sync` use. For the
high-level sync model, see `ARCHITECTURE.md`. For the flag list, see the
README.

## Laptop-to-server sync over SSH

The most common setup: a working directory on a laptop, mirrored to the same
path on a server.

### First run on the laptop

```sh
m3sync -v ~/projects/notes user@server.example.com:projects/notes
```

What happens:

- The laptop has no `.m3sync/` yet, so the script initializes one.
- Because the target has no `.m3sync/` either, the run is one-way: push
  only.
- When the push finishes, `finalize_sync` initializes `.m3sync/` on the
  target over SSH.

### Every subsequent run

```sh
m3sync -v ~/projects/notes user@server.example.com:projects/notes
```

Both sides now have `.m3sync/`. The script detects this and enters
full-duplex mode: pull from the server first (excluding anything the
laptop has touched since the last run), then push.

### Running from the other side

You can also run `m3sync` from the server with the laptop as the target,
but only if the server can reach the laptop over SSH. Most setups don't
have inbound SSH to a laptop, so in practice people run `m3sync` only from
the laptop side and let full-duplex handle the server's edits. That is
fine and is what the script is designed for.

### SSH configuration tips

`m3sync` calls `ssh` without flags, so it inherits your usual `~/.ssh/config`.
If your target needs a specific key, port, or user, set it there:

```
Host sync-box
    HostName server.example.com
    User backup
    Port 2222
    IdentityFile ~/.ssh/id_ed25519_backup
```

Then use `sync-box:projects/notes` as your target URI.

## Three-way rotation: caveats

`m3sync` has no concept of a third party. If you want to keep three machines
in step -- say laptop (L), desktop (D), server (S) -- you have to pick a
topology and be strict about it.

- **Hub and spoke (recommended).** Treat S as the hub. Run `m3sync` from L
  to S and from D to S. Never run L to D directly. Each spoke keeps its
  own `.m3sync/` state against the hub, and changes propagate via the hub
  one round-trip later.
- **Chain.** L to D, then D to S. Works, but changes take two runs to
  propagate end to end, and the middle node is on the critical path.
- **Mesh (not recommended).** All three pairs. Each directory now has
  `.m3sync/` state entangled with multiple peers, and there is no
  coordination between those states. You will eventually lose data.

The underlying reason: `previous-state` is a single file. It describes the
last run against whichever peer ran most recently. Running against a
different peer invalidates the assumption that `delta` reflects real
source-side changes, because some of those "changes" were actually just
writes from the other peer's pull.

Practical rule: one `.m3sync/` per source directory, one peer per
`.m3sync/`.

## Settings file

With `-o` on the command line, `m3sync` reads `.m3sync/settings` on the
source and applies overrides. Format (see `set_overrides`, line 138 of
`m3sync`):

- One setting per line.
- `key value`, separated by whitespace.
- Unknown keys are silently ignored.

Known keys:

- `enabled true|false` -- when `false`, `m3sync` logs an error and exits
  without syncing. Use this to temporarily disable a directory from being
  synced without removing its cron entry.
- `mode <string>` -- sets the initial mode. The script will still promote
  to `full-duplex` automatically if both sides are initialized, so the
  main use is pinning a directory to `mirror` or similar. In practice,
  leaving `mode` unset is fine.

Example `.m3sync/settings`:

```
enabled true
mode mirror
```

To disable a directory:

```
enabled false
```

Then invoke with `-o`:

```sh
m3sync -o ~/projects/notes user@server:projects/notes
```

Without `-o`, the settings file is ignored and the command line wins.

## Interpreting the changelog

Each run produces `.m3sync/changelog/<YYYYMMDDHHMM>/` on the source. It
contains:

- `previous-state` -- the file listing as of the run *before* this one.
- `delta` -- the `diff` between that `previous-state` and the
  `current-state` that was built for this run. `<` lines are entries that
  disappeared, `>` lines are entries that appeared.

To see what changed on a given run:

```sh
ls .m3sync/changelog/
# 202604180905
# 202604181412
# 202604181542

cat .m3sync/changelog/202604181542/delta
```

A typical entry looks like:

```
5a6,7
> docs/NEW-FILE.md
> docs/ANOTHER.md
12d13
< notes/old-idea.md
```

Three things to remember when reading the changelog:

- It tracks source-side adds and removes, not modifications. A file that
  was edited but not renamed will not show up in `delta`.
- It is a snapshot of the script's view of the source at that minute, not
  a record of the rsync transfer itself.
- It does not include what came from the target side during the pull
  phase. For that, look at `.m3sync/backup/<timestamp>/`.

## Dry-run workflow

`-n` is the safest way to see what a run will do. It:

- Computes full state as usual.
- Snapshots `current-state` to `restore-state` before the rsyncs.
- Passes `-n` to both rsync invocations (verbose is forced so you see the
  transfer plan).
- Restores `current-state` from `restore-state` in `finalize_sync` so the
  next real run sees the correct baseline.

A typical iteration loop:

```sh
# Preview.
m3sync -n ~/projects/notes user@server:projects/notes

# Adjust (edit .cvsignore, remove stray files, etc.).

# Real run.
m3sync -v ~/projects/notes user@server:projects/notes
```

Do not mix `-n` and `-o` the first time you use a settings file -- make
sure you know what the settings file says before you let it override your
flags.

## Copying `.cvsignore` with `-c`

`rsync -C` (which `m3sync` always passes) uses `.cvsignore` files to skip
build artifacts, `.git/`, editor junk, and so on. The list of ignores is
the union of the built-in CVS list plus whatever is in a `.cvsignore` file
in each directory plus `$HOME/.cvsignore`.

When the target is remote, your laptop's `~/.cvsignore` is not visible to
the remote `rsync`. Passing `-c` copies it once:

```sh
m3sync -c ~/projects/notes user@server:projects/notes
```

This runs `rsync -a ~/.cvsignore <host>:.cvsignore` before the main sync.
Re-run it after you change `~/.cvsignore`. For a local target this flag is
a no-op (the local `rsync` already sees your home).

## Cron

A reasonable cron entry for an hourly sync, quiet on success:

```
17 * * * * /usr/local/bin/m3sync $HOME/projects/notes user@server:projects/notes >/dev/null 2>&1
```

Use `-v` only if you want mail from cron on every run. The `EXIT` trap
releases the lock on any failure, so a killed run during a transient
network outage will not block the next one -- unless the process was
killed with `SIGKILL`, in which case the lock directory has to be removed
by hand. See `ARCHITECTURE.md` for details.
