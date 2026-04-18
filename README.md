# m3sync

`m3sync` is a small shell script that wraps `rsync` to provide bi-directional,
non-concurrent file synchronization between two directories on one or more
machines. It is designed to be portable, dependency-light, and understandable
in a single sitting: the entire tool is a single POSIX-ish shell script that
relies on `rsync`, `find`, `diff`, `grep`, and `sed`. It is not a CRDT, not a
replacement for Dropbox or Syncthing, and not safe for concurrent writers. It
is, however, a useful tool for keeping a working directory in step across a
laptop and a server when you control when each side is modified.

## Requirements

- `rsync` on both hosts.
- A shell that supports `typeset` with attribute flags (e.g. `ksh`, `bash`,
  `zsh`, `mksh`). The shebang is `#!/usr/bin/env sh`, but the script uses
  `typeset -r`, `typeset -i`, and `[[ ... ]]`, so a strict POSIX `sh` such as
  `dash` will not run it.
- `find`, `diff`, `grep`, `sed`, `sort`, `colrm`, `mkdir`, `mv`, `cp`, `touch`,
  `stat` (all standard on any Unix-like system).
- `ssh` is only required if the target is on a remote host.

## Installation

Drop the script somewhere on your `PATH` and mark it executable:

```sh
install -m 0755 m3sync /usr/local/bin/m3sync
```

Or, without `install`:

```sh
cp m3sync ~/bin/m3sync
chmod +x ~/bin/m3sync
```

## Quick start

One-way mirror from a local directory to a local target (no prior state on
either side, so the first run initializes state on the source only):

```sh
m3sync ~/projects/notes /mnt/backup/notes
```

Bi-directional sync between a laptop and a server. Run this once from each
side, or just keep running it from one side; the second run will enter
full-duplex mode automatically once both sides have a `.m3sync/` directory:

```sh
m3sync ~/projects/notes user@server.example.com:projects/notes
```

Dry run to preview what would change, with verbose output:

```sh
m3sync -n ~/projects/notes user@server.example.com:projects/notes
```

## Usage

```
m3sync [-cdhnov] <source_dir> <target_uri>
m3sync -h
```

`source_dir` is always a local path. `target_uri` is either a local path or
`host:path` (the same form `rsync` accepts for SSH transport).

### Flags

Each flag is described below with a minimal example.

- `-c` Copy the current user's `~/.cvsignore` to the remote host before
  syncing. Only meaningful when the target is remote; a local target is a
  no-op with a notice.

  ```sh
  m3sync -c ~/projects/notes user@server:projects/notes
  ```

- `-d` Log debug messages to stderr. Implies nothing else, but useful while
  learning the tool.

  ```sh
  m3sync -d ~/projects/notes /mnt/backup/notes
  ```

- `-h` Print the help text and exit. Also triggered by an unknown option.

  ```sh
  m3sync -h
  ```

- `-n` Dry run. The script computes state and invokes `rsync` with `-n`, then
  restores the pre-run `current-state` file so the next real run still sees
  the correct baseline. Implies verbose output on the `rsync` side.

  ```sh
  m3sync -n ~/projects/notes /mnt/backup/notes
  ```

- `-o` Allow the `.m3sync/settings` file inside the source directory to
  override command-line options. Without this flag the settings file is
  ignored. See `docs/USAGE.md` for the on-disk format.

  ```sh
  m3sync -o ~/projects/notes /mnt/backup/notes
  ```

- `-v` Log warnings and notices to stderr, and pass `-v` through to `rsync`.

  ```sh
  m3sync -v ~/projects/notes /mnt/backup/notes
  ```

## State directory

Each synced directory gets a `.m3sync/` subdirectory on first run. It holds
a `settings` file, a `last-run` marker, `previous-state` and `current-state`
file listings, a `delta`, a `protected-list`, a `lock/` mutex, a timestamped
`backup/` tree for files replaced or deleted by `rsync`, and a `changelog/`
tree of per-run state snapshots. See `docs/ARCHITECTURE.md` for the full
picture.

## Limitations and when not to use this

Be honest with yourself about these before trusting `m3sync` with anything
you care about:

- **Non-concurrent only.** `m3sync` assumes the source and target are not
  modified simultaneously. If both sides change the same file between runs,
  the older write is lost.
- **Last-write-wins conflict resolution.** Conflicts are resolved by `rsync
  -u`, which compares modification times. Clock skew, filesystem timestamp
  granularity, and `touch` all affect the outcome. There is no merge, no
  prompt, and no conflict file.
- **Minute-precision timestamps.** Internal bookkeeping (backup paths,
  changelog directories) uses `%Y%m%d%H%M`. Two runs started in the same
  minute will collide.
- **No rename detection.** A renamed file looks like a deletion and a
  creation. `rsync` will retransmit it in full.
- **No true CRDT, no vector clocks, no content-addressed store.** State is
  a pair of file listings and a lock directory. It is enough to drive a
  sane bi-directional `rsync`, and no more.
- **Lock is advisory and local.** The `.m3sync/lock/` directory prevents two
  `m3sync` processes from stepping on the same source, but it does not
  protect against other tools writing the tree.
- **Not safe for binary databases under active writers** (sqlite, maildir
  locks, git objects mid-rebase, etc.). Stop the writer or use a tool that
  understands the format.

If your use case is "multiple people edit at once and the tool figures it
out", use Syncthing, Nextcloud, or a real VCS. If your use case is "I want
my dotfiles and notes to follow me between two machines and I run it by
hand or in cron when I remember", `m3sync` is a reasonable fit.

For known issues the maintainer is tracking, see `docs/FINDINGS-bugs.md`.

## Further reading

- `docs/ARCHITECTURE.md` -- the sync model, state files, and algorithm.
- `docs/USAGE.md` -- worked examples, settings file reference, changelog
  layout, dry-run workflow.
- `docs/CONTRIBUTING.md` -- style, tests, and repository layout.
- `docs/FINDINGS-bugs.md` -- known bugs (maintained by a separate review
  pass).
- `docs/FINDINGS-algorithm.md` -- deeper algorithmic analysis.

## License

BSD 3-Clause. See `LICENSE`.
