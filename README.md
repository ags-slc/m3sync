# m3sync
Minimalistic, multi-machine sync.

`m3sync` is a multi-directional (non-concurrent) file synchronization tool, with minimal requirements. In fact, the only requirement (other than POSIX) is the wonderfully robust and efficient `rsync`.

While `m3sync` does not allow for concurrency, it solves for many common use cases, and can be an effective synchronization utility, provided the user understands the limitations.

POSIX and mostly POSIX-compliant systems should be compatible with `m3sync`. The feature set is purposefully minimal to acheive maximum portability, and in order to limit external dependencies.

This tool began as a thought experiment on how to create a bi-directional file synchronization tool using only utilities that are commonly available at every (POSIX) command line.

```
Usage:
  m3sync [-cdhnov] source_dir target_uri
```
