#!/bin/sh
# BUG-10: rsync -C (--cvs-exclude) was in the base options, so a project's
# .git/, *.o, *~, and #*# files were silently skipped — a sync tool
# should NOT make this decision for the user. The -c command-line flag
# exists to opt into cvsignore behaviour; the default should not.

setup_env

# Simulate a project directory with a .git dir and a build artifact that
# rsync -C's default excludes would hide.
mkfile "${SRC}/.git/HEAD" "ref: refs/heads/main"
mkfile "${SRC}/main.c" "int main() { return 0; }"
mkfile "${SRC}/main.o" "binary-ish"
mkfile "${SRC}/editor-backup~" "autosave"

run_sync
assert_equal "${RUN_RC}" "0" || exit 1

# All of these must propagate now that -C is gated behind -c.
assert_file_exists "${DST}/.git/HEAD"        || exit 1
assert_file_exists "${DST}/main.c"           || exit 1
assert_file_exists "${DST}/main.o"           || exit 1
assert_file_exists "${DST}/editor-backup~"   || exit 1
