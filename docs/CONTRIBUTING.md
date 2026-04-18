# Contributing

Short guide for people working on `m3sync` itself.

## Scope

`m3sync` is deliberately small. Changes that add dependencies, add commands,
or substantially grow the script are unlikely to be accepted. Changes that
fix correctness bugs, improve portability, or clarify existing behavior are
very welcome.

## Style

The script targets "mostly POSIX" shell with ksh-style `typeset`. A few
rules to keep it coherent:

- **One file.** `m3sync` is a single script by design. Do not split it into
  a library tree.
- **`typeset` for all variables.** Use `typeset -r` for constants,
  `typeset -i` for integers, `local` inside functions. The existing code
  is consistent about this; follow the pattern.
- **Quote expansions.** `"${var}"`, not `$var`, especially for anything
  that can contain spaces or is user-supplied (paths, URIs, host names).
  The current script is not perfect about this; patches that tighten
  quoting without changing behavior are welcome.
- **`[[ ... ]]` over `[ ... ]`.** The script already requires a shell that
  supports it.
- **Prefer functions.** Named functions with a short header comment
  describing params and intent are the convention. See `log_msg`,
  `filtered_find`, `prepare_sync` for examples.
- **No external tools beyond the standard Unix set.** `rsync`, `find`,
  `diff`, `grep`, `sed`, `sort`, `colrm`, `mkdir`, `mv`, `cp`, `touch`,
  `stat`, `ssh`. Adding a dependency is a significant change and needs
  justification.
- **No emoji, no color codes, no spinners.** Logging is plain text to
  stderr via `log_msg`.

## Running the tests

The test suite lives in `tests/`. The entry point is `tests/run.sh`:

```sh
sh tests/run.sh
```

It runs every `tests/test_*.sh` in the directory against the `m3sync`
script at the repository root, sets up and tears down scratch directories
under a temp location, and exits non-zero if any test fails. Individual
tests can be run directly:

```sh
sh tests/test_full_duplex_basic.sh
```

Shared helpers live in `tests/lib.sh`. See `tests/README.md` for the
authoring conventions used by the test suite.

When you add a feature or fix a bug, add a test that would have failed
before your change. Regression tests are cheap insurance for a script
that touches people's files.

## Repository layout

```
m3sync/
  m3sync                 the script itself
  README.md              user-facing overview
  LICENSE                BSD 3-Clause
  docs/
    ARCHITECTURE.md      sync model, state, algorithm
    USAGE.md             worked examples, settings, changelog
    CONTRIBUTING.md      this file
    FINDINGS-bugs.md     known bugs (review output)
    FINDINGS-algorithm.md algorithmic analysis (review output)
  tests/
    run.sh               test runner
    lib.sh               shared helpers
    test_*.sh            individual tests
    README.md            test suite conventions
  .claude/
    agents/              agent definitions (see below)
```

## Parallel agent workflow

This repository uses a set of Claude Code subagents, defined under
`.claude/agents/`, to keep the codebase clean without any one agent doing
everything at once. At a high level the roles are:

- **bug-hunter** -- reads the script carefully, catalogs defects with line
  numbers, and writes them to `docs/FINDINGS-bugs.md`. Does not edit code.
- **test-writer** -- authors tests under `tests/` that exercise the
  behaviors described by the bug-hunter and the architecture docs. Does
  not edit `m3sync`.
- **refactor-finisher** -- applies small, targeted fixes to `m3sync`
  based on the findings, one at a time, with the test suite as the
  gate.
- **reviewer** -- reads proposed changes and comments on correctness,
  style, and scope. Does not commit.

The agents are designed to run in parallel without stepping on each other:
each one owns a specific set of paths. If you are adding a new agent,
declare its owned paths clearly in its definition and do not overlap with
an existing agent's territory.

Human contributors can ignore all of that and work the normal way: clone,
branch, edit, test, open a PR.

## Commits and PRs

- Keep commits small and focused. One logical change per commit.
- Commit messages: short imperative subject, optional body explaining the
  why.
- PRs should describe the observable change and link to any relevant
  finding in `docs/FINDINGS-bugs.md`. If you are fixing a bug, include
  the test that covers it.
