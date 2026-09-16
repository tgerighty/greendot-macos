# greendot

macOS menu-bar status-page monitor. Product and parsers: [README.md](README.md). Domain terms: [CONTEXT.md](CONTEXT.md). Commands: `Makefile`.

## Gitar

After you open a GitHub pull request, post one PR comment whose body is exactly `Gitar review`:

```bash
gh pr comment <n> --body 'Gitar review'
```

Done when that exact comment exists on the PR.

Automatic Gitar reviews may be paused. The comment is the trigger.
Treat a pending Gitar check as optional. Continue when the required checks pass.
