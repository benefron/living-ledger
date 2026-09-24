# Contributing

Thanks for looking. Issues and pull requests are welcome.

## Before you open a pull request

```bash
bash tests/run_tests.sh      # end to end, in throwaway repos; never touches your ~/.claude
python3 tests/test_merge.py  # the merge driver
```

Both must pass (CI runs them on macOS and Linux). Windows isn't in CI; if you use the ledger there, reports are especially welcome.

- **Every commit carries a ledger trailer** — this repository keeps its own ledger, so the
  `commit-msg` gate applies here too. `Decision:`, `Finding:`, `Opens:`, `Fixed:` … or
  `Ledger: none — <reason>`. Run `./install.sh .` once in your clone to activate the hooks.
- **A behaviour change comes with a test** in `tests/run_tests.sh`, and a line in `CHANGELOG.md`.
- **Keep the per-repo hooks dependency-free**: bash, POSIX tools, git and the Python 3 standard
  library only. They are copied into every user's repository.
- **Nothing reads the network at session start**, and nothing writes outside a commit — see
  "What runs where" in the README before adding a hook.
- Changes to anything under `templates/` reach users' repositories only through
  `/ledger-init --upgrade`. If existing installs must change, bump `ledger-template-version` in
  every template file and describe the change in `ll_version_changes` (`lib/common.sh`).

## Reporting a bug

Please use the bug-report template: your OS, `git --version`, `python3 --version`, the output
that went wrong, and — if it is about a repository's ledger — `.claude/ledger.conf` and the
relevant commit message (redact anything private).
