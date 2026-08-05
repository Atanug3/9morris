# Git hooks

This folder holds repo-managed git hooks (versioned so they travel with the repo).

## Enable (once per clone)
Git does not auto-run hooks from a custom path for security. Enable them with:

```bash
git config core.hooksPath .githooks
```

That's it — on Windows, hooks run via Git Bash automatically.

## What `pre-commit` does
- **Blocks** any commit containing a file larger than **100 MB** (GitHub's hard limit).
- **Warns** on files larger than **50 MB** (GitHub warns here too).
- **Warns** when a newly added file is **binary** (in case it was staged by mistake).

Override the thresholds per-invocation if needed:
```bash
HARD_LIMIT_BYTES=209715200 git commit -m "..."   # 200 MB hard limit
```

Emergency bypass (not recommended): `git commit --no-verify`.
