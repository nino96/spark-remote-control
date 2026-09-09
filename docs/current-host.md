# Current GX10 inventory

Observed on 2026-09-04; Codex, Claude, OpenCode, GitHub Copilot CLI, and the
GitHub CLI (`gh`) rows refreshed 2026-09-09. Run `sparkctl doctor` rather than
treating this file as live state.

| Area | Observed state | Design consequence |
| --- | --- | --- |
| Platform | Ubuntu 24.04.4, arm64, kernel 6.17 NVIDIA | Use Noble-compatible ARM64 packages |
| Codex | 0.153.4 in `~/.local/bin`; has `codex remote-control` (shared app-server daemon); one is already running by hand, unmanaged (no systemd unit, so it does not survive reboot) | Vendor remote control exists; not toolkit-managed (issue #2) |
| Claude | 2.1.266 in `~/.local/bin` | Remote Control can be project-scoped |
| GitHub Copilot CLI | 1.0.83 at `~/.nvm/versions/node/v24.19.0/bin/copilot`; has `--remote`/`--connect` live-session attach | Vendor remote control exists; not toolkit-managed (issue #3) |
| OpenCode | 1.18.29 at `~/.opencode/bin/opencode`, outside any toolkit-managed path | `config/versions.env` pins 1.18.27; reconcile before treating the install as managed |
| GitHub CLI (`gh`) | 2.45.0 at `/usr/bin/gh` (Ubuntu package) | Available for branch/PR workflows; not otherwise used by this toolkit |
| Bubblewrap | 0.9.0; AppArmor denies namespace capabilities | Install the stacked Ubuntu profile |
| Tailscale | 1.102.2, connected | Use Serve, not a public listener |
| Tailscale Serve | HTTPS `/` already proxies `127.0.0.1:11470` | Do not reset or replace the existing route |
| Docker | 29.2.1, rootful; user is in `docker` group | Treat local agents as root-equivalent if they can call Docker |
| vLLM | Existing `vllm-server` container, restart `unless-stopped` | Monitor it; do not launch another service |
| vLLM endpoint | Host port 8000 on all IPv4/IPv6 interfaces | Recreate with a loopback-only bind when operationally convenient |
| SearXNG | Host port 8888 on all interfaces | Review whether broad LAN exposure is intended |

The current vLLM container serves `qwen36` from
`nvidia/Qwen3.6-35B-A3B-NVFP4` and uses a named Hugging Face cache volume.
Changing its bind requires recreating the container, so this repository only
reports the exposure until that external deployment is brought under source
control.

The current user belongs to the `docker` group. Docker documents this as
root-level host access. Running OpenCode or Claude under this account therefore
does not create a privilege boundary even when systemd hardening is enabled.
A later hardening phase should use a dedicated account without Docker access,
or a separate rootless container engine for agent-created containers.

