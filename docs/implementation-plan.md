# Implementation plan

## Assessment of the proposed setup

The hybrid direction is sound. The implementation should avoid pretending the
four agent products are one interchangeable scheduler. Their common handoff is
GitHub, while their authentication, quotas, permissions, persistence, and
review flows remain provider-specific.

The GX10 should provide a durable workspace, not a single daemon with ambient
access to the whole machine. OpenCode Web is the primary local entry point;
Claude Remote Control is created per project; Codex and Copilot are invoked on
demand. vLLM is an optional dependency and should not block the remote-control
stack.

Subscription entitlements, product names, permission modes, pricing, and CLI
flags change frequently. Before relying on any of those operationally, verify
them against current first-party documentation. This repository deliberately
does not encode billing assumptions.

## Phase 1: safe host foundation

- Initialize the repository and use `main` as the default branch.
- Run `sparkctl doctor` and retain its output when troubleshooting.
- Install the scoped bubblewrap AppArmor profile and verify a user plus network
  namespace can be created.
- Run all long-lived processes as systemd user services.
- Enable user lingering only if services must start before interactive login.

Exit condition: `make check` passes and `sparkctl bwrap test` succeeds.

## Phase 2: interactive local environment

- Install and authenticate OpenCode using its official installer/provider flow.
- Generate a strong `OPENCODE_SERVER_PASSWORD` in the external environment
  file.
- Enable `spark-opencode.service` and confirm it listens only on loopback.
- Publish the loopback listener with Tailscale Serve and test from another
  tailnet device.

Exit condition: OpenCode is reachable through the tailnet but not through the
GX10's LAN or public interfaces.

## Phase 3: provider-specific paths

- Connect supported OpenCode providers one at a time and confirm which account
  or billing pool each model uses.
- Authenticate Codex and use cloud delegation for repository-contained tasks.
- Add Claude Remote Control only to selected project directories.
- Configure Copilot's cloud agent at the GitHub repository level when its
  issue-to-PR workflow is useful.

Exit condition: each path can make a small test change on a disposable branch,
run tests, and produce a reviewable diff without accessing unrelated projects.

## Phase 4: local inference and containers

- Choose and benchmark a model that fits available GX10 memory.
- Record the existing model, image digest, launch arguments, and cache volume before recreating the container.
- Bring the existing `vllm-server` deployment under source control and recreate it with a loopback-only port bind.
- Add Docker Compose files per development project rather than granting one
  global agent container access to every project and the Docker socket.

Exit condition: local inference survives a user-service restart and is
explicitly selectable without becoming an accidental fallback for difficult
tasks.

## Phase 5: operations

- Back up only source repositories and reviewed configuration, not ephemeral
  model caches or provider tokens.
- Use `sparkctl update`; pin known-good Git tags before large operational
  changes.
- Add a timer for a read-only health report before considering unattended
  upgrades.
- Review service logs, provider sessions, Tailscale policy, and project access
  quarterly.

Automatic third-party CLI upgrades are intentionally deferred. Each provider
uses a different package channel and may introduce config migrations. A future
updater should detect installation provenance, show the planned version change,
and require explicit confirmation before touching provider binaries.

