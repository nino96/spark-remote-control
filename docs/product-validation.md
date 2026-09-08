# Product validation

Verified against first-party documentation on 2026-09-04, and the Claude Code
section re-verified on 2026-09-08. Product entitlements, quotas, preview
status, and CLI flags are volatile; re-check them before automating
billing-sensitive behavior.

## Codex

- Codex Cloud is a real asynchronous path that runs work in isolated cloud
  environments and can integrate with GitHub, GitLab, Linear, and Slack.
- It is no longer accurate to describe Codex only as a ChatGPT Plus feature;
  availability and limits vary by current ChatGPT plan.
- The CLI currently exposes experimental cloud commands, including
  `codex cloud exec`.
- Do not model a Linux GX10 as equivalent to the documented desktop Remote
  host workflow. Keep Codex local as an on-demand CLI and use Codex Cloud for
  asynchronous repository work.

Sources: [Codex Cloud](https://learn.chatgpt.com/docs/cloud),
[developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli),
and [sandboxing](https://learn.chatgpt.com/docs/sandboxing).

## Claude Code

- Claude Code on the web is a true hosted path for supported subscriptions.
- `claude remote-control` (server mode) keeps execution and filesystem access
  on the GX10 and communicates outbound through Anthropic's relay; it is not a
  cloud VM. It is a plain foreground process, not a self-daemonizing one. This
  repository offers a hardened systemd user service for multi-session
  availability and a tmux helper for one supervised interactive session.
- Server mode gives up and exits after roughly 10 minutes with no network
  reachability at all (distinct from ordinary reconnect handling, which
  retries indefinitely). Because that timeout can be a clean exit, the systemd
  unit uses `Restart=always` rather than `Restart=on-failure`. The restart
  restores server availability but can create a new session; it does not
  guarantee recovery of every session the previous server managed.
- Session continuity is explicit. The current CLI supports `--continue` for
  the most recently recorded conversation in a directory and `--resume` for
  selecting a conversation. `sparkctl project tmux` keeps the interactive
  terminal available and does not guess which conversation to resume.
- Server mode supports `--spawn <same-dir|worktree|session>` (default
  `same-dir`) and `--capacity <N>` (default 32, incompatible with
  `--spawn session`). `worktree` gives each on-demand session its own git
  worktree so concurrent sessions in one project don't edit the same files;
  it requires the project directory to be a git repository. The persistent
  service exposes `same-dir`, `worktree`, and capacity; its project interface
  intentionally leaves one-session operation to the tmux workflow.
- `acceptEdits` is not autonomous shell execution. `auto` remains the sensible
  local default when supported (it is a documented, valid `--permission-mode`
  value); `bypassPermissions` belongs only inside an intentionally isolated VM
  or container.
- Auto/Bypass are configured on the local host rather than selected from the
  Remote Control UI.

Sources: [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web),
[Remote Control](https://code.claude.com/docs/en/remote-control), and
[permission modes](https://code.claude.com/docs/en/permission-modes).

## GitHub Copilot

- Copilot cloud agent is an asynchronous GitHub issue/branch/PR worker backed
  by an ephemeral Actions environment.
- The interactive `copilot --cloud --experimental` sandbox is a different,
  separately metered product.
- The current individual Pro allowance is 1,000 base plus 500 flex AI credits,
  not the 1,000 total stated in the original chat.
- Local Linux sandboxing uses bubblewrap, so the AppArmor repair in this
  repository helps both Codex and Copilot sandbox paths.

Sources: [Copilot cloud agent](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent),
[cloud and local sandboxes](https://docs.github.com/en/copilot/concepts/about-cloud-and-local-sandboxes),
and [individual usage billing](https://docs.github.com/en/copilot/concepts/billing/usage-based-billing-for-individuals).

## OpenCode

- `opencode web` is current and supports explicit host/port settings plus HTTP
  Basic authentication through `OPENCODE_SERVER_PASSWORD`.
- Current provider flows support ChatGPT Plus/Pro and GitHub Copilot logins.
- OpenCode warns against unofficial use of Claude Pro/Max credentials; use the
  Claude CLI or a permitted API provider instead.
- The pinned 1.x configuration uses the singular `permission` object. Rules
  use last-match-wins ordering. `--auto` affects permissions that would
  otherwise ask, while explicit deny rules remain enforced.

Sources: [OpenCode CLI](https://opencode.ai/docs/cli/),
[providers](https://opencode.ai/docs/providers/), and
[permissions](https://opencode.ai/docs/permissions/).
