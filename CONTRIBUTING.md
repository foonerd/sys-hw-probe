# Contributing to sys-hw-probe

Thanks for helping! Please follow these basics:

## Tooling
- Bash 4+, ShellCheck, shfmt, BATS
- Keep scripts POSIX/Bash-friendly and readable

## Workflow
1. Fork -> feature branch
2. `make fmt lint test`
3. Open PR with:
   - Purpose and scope
   - Platforms tested (x86, Pi, Wayland/Xorg, etc.)
   - Sample output (redact serials/MACs)

## Style
- `#!/bin/bash`, `set -u -o pipefail`
- Provide `--help` and sane defaults
- No destructive actions without explicit flags
- Prefer `jq`, `awk`, `sed`, `grep` for parsing;
  guard for missing tools

## Licensing
- MIT. By contributing, you agree your contributions are MIT-licensed.
