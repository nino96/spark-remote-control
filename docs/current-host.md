# Current GX10 inventory

Observed on 2026-09-04. Run `sparkctl doctor` rather than treating this file as
live state.

| Area | Observed state | Design consequence |
| --- | --- | --- |
| Platform | Ubuntu 24.04.4, arm64, kernel 6.17 NVIDIA | Use Noble-compatible ARM64 packages |
| Codex | 0.153.2 in `~/.local/bin` | Keep as an on-demand CLI |
| Claude | 2.1.251 in `~/.local/bin` | Remote Control can be project-scoped |
| OpenCode | Not installed | Install the pinned npm package explicitly |
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

