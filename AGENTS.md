# Agent guidance

- Keep host-changing operations explicit, idempotent, and reversible.
- Never commit credentials, provider tokens, generated environment files, or machine-specific state.
- Prefer user-level systemd services. Require `sudo` only for host security policy or package management.
- Treat OpenCode and Claude sessions as privileged access to the selected project checkout.
- Bind web services to loopback and expose them only through Tailscale unless the user explicitly chooses otherwise.
- Use `gpt-5.6-luna` subagents at `high` or `xhigh` reasoning for lightweight parallel tasks when subagents are available.
- Run `make check` after shell, configuration, or documentation changes.

