# Architecture

## Boundary model

```text
phone / laptop / tablet
  |
  +-- provider UIs -------------------- cloud agent VMs
  |                                      |
  |                                      +-- GitHub branch / PR
  |
  +-- private tailnet
         |
         +-- Tailscale Serve
                |
                +-- 127.0.0.1:4096 OpenCode Web
                         |
                         +-- selected GX10 projects
                         +-- Docker and local services
                         +-- optional 127.0.0.1:8000 vLLM

Claude web/mobile -- outbound provider relay -- Claude Remote Control
                                              |
                                              +-- one explicit project

Codex web/mobile -- vendor remote control -- spark-codex-remote.service
                                                     |
                                                     +-- shared app-server daemon
                                                         (every project under $CODEX_HOME)

Copilot web/mobile -- vendor remote control -- local CLI session
                                                       |
                                                       +-- not managed
                                                           by this
                                                           toolkit (issue #3)
```

There are two independent trust boundaries:

1. Cloud agents receive a GitHub repository and return reviewable branches or
   pull requests. They do not receive access to the GX10.
2. Local agents run in the real development environment. They can reach only
   the projects and host services permitted by their process and sandbox.

## Why this split

Cloud execution is best for bounded tasks with a reproducible repository.
Local execution is best for Docker stacks, private databases, home services,
GPU models, large caches, and exploratory sessions. Remote Control exposes the
local environment remotely; it is not equivalent to an independent cloud job.

## Managed services

| Unit | Default | Exposure | Purpose |
| --- | --- | --- | --- |
| `spark-opencode.service` | disabled | loopback | Persistent OpenCode Web UI |
| `spark-claude-remote@NAME.service` | disabled | outbound relay | Always-available, multi-session Claude access to one project |
| `sparkctl project tmux NAME` | on demand | outbound relay | One interactive Claude session with explicit resume control |
| `spark-codex-remote.service` | disabled | outbound relay | Boot-persistent lifecycle for the shared, machine-wide Codex app-server daemon |
| Existing `vllm-server` container | external | currently all interfaces | Local model API; monitor now, migrate later |

Codex is now in this table via `spark-codex-remote.service`, a singleton unit
rather than a per-project template: `codex remote-control` manages one shared
app-server daemon per `$CODEX_HOME`, not one daemon per checkout, so a
`@NAME` template would misrepresent it. Copilot remains outside this table:
this toolkit manages no unit, launcher, or wrapper for it. Its CLI ships
vendor-native remote control of a live session (`copilot --remote`) that
attaches to one interactive session rather than a background daemon, closer
in shape to the `sparkctl project tmux` pattern than to a systemd service.
Adding toolkit support for Copilot is tracked in issue #3.

## Security decisions

- No toolkit-managed service binds to `0.0.0.0` by default.
- Tailscale is the network access layer; the application password remains a
  second control where supported.
- Provider login remains interactive. Setup scripts never scrape or copy auth
  tokens.
- Each Claude service names one checkout rather than inheriting `~/code`.
  This is a Claude-specific property, not a general one. Codex's daemon is
  machine-wide and shared, and it reparents to PID 1 as soon as it detaches,
  so `spark-codex-remote.service`'s hardening directives constrain only the
  short-lived `codex remote-control start` process that launches it, not the
  daemon itself. There is no systemd unit boundary around a Codex project the
  way there is for a Claude checkout. Project scoping for Codex therefore
  comes entirely from Codex's own sandbox/permission profile
  (`codex-linux-sandbox`, bubblewrap, the AppArmor profile this repo
  installs), not from the unit. This is a real asymmetry with the Claude
  unit, not a caveat: treat any project isolation claim for Codex as backed
  by Codex's sandbox, never by systemd.
- `spark-codex-remote.service` is `Type=oneshot` with `RemainAfterExit=yes`
  and no `Restart=`. `ExecStart` runs `codex remote-control start`, which
  launches the daemon and returns; the daemon then detaches to PPID 1 and
  supervises itself with its own `pid-update-loop` process, so there is no
  long-lived process left in the unit for systemd to restart. The unit's job
  is boot persistence and a documented start/stop/status lifecycle, not
  process supervision. Contrast this with the Claude unit: Claude needs
  `Restart=always` because `claude remote-control` itself is the long-lived
  process the unit holds open, and it deliberately exits after a give-up
  timeout; Codex's daemon has no equivalent foreground process for the unit
  to supervise, so there is nothing for a `Restart=` directive to act on.
- Ubuntu's stacked `bwrap`/`unpriv_bwrap` policy allows setup and strips child
  capabilities; the global
  unprivileged-user-namespace restriction stays enabled.
- Systemd units are linked to this checkout, making updates immediate and
  rollback equivalent to checking out an earlier known-good Git revision and
  running `sparkctl setup`.
- `claude remote-control` stays in the foreground and exits on its own after
  roughly 10 minutes offline; `spark-claude-remote@NAME.service` uses
  `Restart=always` (not `on-failure`) so a clean exit from that give-up also
  gets restarted, with a `StartLimitBurst` so a persistently broken project
  (bad credentials, missing directory) stops retrying instead of looping
  forever. A restart restores server availability but does not guarantee that
  sessions served by the previous process are reattached.
- `sparkctl project add` can set `--spawn worktree` so on-demand sessions get
  isolated git worktrees instead of sharing one checkout, and `--capacity` to
  bound concurrent sessions per project.
- `sparkctl project tmux` launches interactive Remote Control inside a
  project-scoped tmux session. It leaves conversation selection and resume
  explicit, and keeps a shell available if Claude exits.

## Secrets

Store service environment values in
`~/.config/spark-remote-control/env` (mode `0600`). Provider CLIs retain their
own credentials in vendor-managed stores. Never copy those stores into this
repository, containers, logs, or cloud-agent prompts.
