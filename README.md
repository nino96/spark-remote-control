# Spark Remote Control

An operations toolkit for turning this always-on ASUS GX10 into a private,
persistent coding workstation while keeping cloud coding agents available for
well-contained GitHub work.

It manages:

- OpenCode Web on loopback for interactive GX10 work.
- Claude Code Remote Control as an opt-in service per project.
- A guarded Ubuntu AppArmor fix for Codex and Copilot bubblewrap sandboxes.
- Health checks for the existing Docker-managed vLLM service.
- User-level systemd units, pinned tool versions, updates, and removal.

Codex and Copilot remain on-demand CLIs. Cloud agents remain provider-managed
and exchange work through GitHub branches and pull requests.

## What was found on this GX10

The box is Ubuntu 24.04.4 on ARM64. Codex and Claude are installed; OpenCode
and the standalone GitHub CLI are not. Tailscale and Docker are active. vLLM
already runs in a container, so this repository monitors it instead of
starting a competing service.

Two existing settings need deliberate treatment:

- AppArmor currently blocks bubblewrap's namespace capabilities. Use the
  included stacked Ubuntu profile.
- Tailscale Serve already proxies HTTPS `/` to `127.0.0.1:11470`. Do not reset
  or overwrite it. Start OpenCode on a separate tailnet HTTPS port.

See [the complete host inventory](docs/current-host.md).

## Quick start

Nothing outside this repository is installed automatically just by cloning it.
Start with:

```bash
make check
make setup
sparkctl tool install opencode
```

Set an OpenCode password:

```bash
openssl rand -base64 36
${EDITOR:-nano} ~/.config/spark-remote-control/env
```

Then authenticate providers interactively and run diagnostics:

```bash
sparkctl auth opencode
make doctor
```

OpenCode's `/connect` flow currently supports OpenAI ChatGPT Plus/Pro and
GitHub Copilot. Do not import Claude Pro credentials into OpenCode; use Claude
Code directly or use a permitted API provider.

## Fix bubblewrap

This machine already has bubblewrap and user namespaces enabled. Ubuntu's
generic `unprivileged_userns` AppArmor profile is denying the capabilities
needed to initialize the isolated network namespace.

Run from a normal terminal so `sudo` can prompt:

```bash
sparkctl bwrap status
sparkctl bwrap install
sparkctl bwrap test
```

The installer uses Ubuntu Noble's stacked `bwrap`/`unpriv_bwrap` policy. It
allows bubblewrap to construct the sandbox, then strips capabilities from the
sandboxed child. It refuses to overwrite an unmanaged profile and never turns
off Ubuntu's global user-namespace restriction.

This profile applies to every `/usr/bin/bwrap` caller on the machine, not only
Codex. If a Flatpak or another bubblewrap-based tool regresses, disable the
profile and re-test before changing global user-namespace settings.

Removal is reversible:

```bash
sparkctl bwrap remove
```

The profile is unloaded and moved under `/etc/apparmor.d/disable/` rather than
being deleted.

## Start OpenCode Web

```bash
sparkctl service enable opencode
sparkctl service status opencode
sparkctl service logs opencode
```

The service refuses to start without a password and refuses any non-loopback
bind. To review a Tailscale Serve command that preserves the existing route:

```bash
sparkctl tailscale status
sparkctl tailscale plan
```

The proposed initial URL uses tailnet HTTPS port `4443`. Keep Funnel disabled.

The sample [OpenCode permission policy](config/opencode/opencode.jsonc.example)
allows normal repository work, asks before pushes and deletion, denies sudo and
force pushes, and keeps external directories behind approval.

## Add Claude Remote Control

Authenticate Claude interactively first. Then register only the checkout it
should access:

```bash
sparkctl project add my-project ~/code/my-project
```

The service uses Claude's `auto` permission mode locally when the selected
account/model supports it. Remote Control uses outbound HTTPS and opens no
inbound listener. Treat `bypassPermissions` as suitable only for a disposable
container or VM.

### Always-available multi-session server

Enable the systemd service when you want the project to accept on-demand
sessions without an attached terminal:

```bash
sparkctl project enable my-project
sparkctl project logs my-project
```

`claude remote-control` is a foreground server process, not a self-daemonizing
one, so `spark-claude-remote@NAME.service` is what actually keeps it running:
`Restart=always` brings it back after a crash, a Ctrl+C-equivalent exit, or the
~10-minute give-up Claude Code performs on an extended network outage.
This restores server availability, but it does not transparently reattach every
session the previous process served. A restart can create a new session;
existing conversations must be resumed explicitly when continuity matters.

By default one project serves every on-demand session from the same checkout,
which can conflict if two sessions edit the same files. Pass `--spawn
worktree` when adding a project to give each on-demand session its own git
worktree instead, and `--capacity N` to cap how many concurrent sessions the
server accepts (Claude Code's own default is 32):

```bash
sparkctl project add my-project ~/code/my-project --spawn worktree --capacity 4
```

`--spawn worktree` requires the project directory to be a git repository.
The managed service intentionally supports only the persistent `same-dir` and
`worktree` modes. Use the tmux workflow below for one interactive session.
Do not run both workflows for the same project at once; `sparkctl` refuses to
start either one while the other is active.

### One resumable session with tmux

For a session you want to supervise and resume deliberately, create or attach
to its project-scoped tmux session:

```bash
sparkctl project tmux my-project
```

On first use this creates `spark-claude-my-project` and starts interactive
`claude --remote-control`. Detach with `Ctrl-b d`; run the same `sparkctl`
command later to attach again. If Claude exits after an extended outage, the
tmux shell remains open. Resume the latest conversation with `claude
--continue`, or select one with `claude --resume`, then run `/remote-control`
inside Claude to expose it again.

tmux does not survive a host reboot, but Claude's saved conversations do. After
a reboot, create the tmux session again and use `claude --resume` if you need a
specific previous conversation. To end the tmux session itself, exit its shell
or run `tmux kill-session -t spark-claude-my-project`.

## Operations

```bash
make doctor
make status
make logs
make update
make check
sparkctl uninstall
```

`sparkctl update` requires a clean worktree and uses `git pull --ff-only`.
OpenCode is pinned in [config/versions.env](config/versions.env); updating it is
an explicit version change followed by:

```bash
sparkctl tool update opencode
```

Runtime configuration is outside Git:

```text
~/.config/spark-remote-control/env
~/.config/spark-remote-control/projects/*.env
```

The current account belongs to the root-equivalent Docker group. Systemd
hardening does not remove that authority. The next hardening phase is a
dedicated agent account without access to the rootful Docker socket.

See [product validation](docs/product-validation.md), [architecture](docs/architecture.md), and the
[implementation plan](docs/implementation-plan.md).
