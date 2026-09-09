#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
readonly TEST_ROOT="$(mktemp -d)"
readonly TEST_CONFIG_ROOT="$TEST_ROOT/config"
readonly TEST_PROJECT_DIR="$TEST_ROOT/project"
readonly TEST_FAKE_BIN="$TEST_ROOT/bin"
readonly TEST_TMUX_LOG="$TEST_ROOT/tmux.log"
readonly TEST_CLAUDE_LOG="$TEST_ROOT/claude.log"
readonly TEST_SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"
readonly TEST_CODEX_LOG="$TEST_ROOT/codex.log"
# A dedicated CODEX_HOME under TEST_ROOT so no test ever touches the real
# ~/.codex on this host (a live Codex daemon may be serving real sessions).
readonly TEST_CODEX_HOME="$TEST_ROOT/codex-home"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

# sparkctl branches on TMUX, so the suite must not inherit the tmux session a
# maintainer is likely running `make check` from. Cases needing the in-tmux
# path set TMUX explicitly; every other case must see it unset.
unset TMUX TMUX_PANE
unset SPARK_TEST_TMUX_HAS_SESSION SPARK_TEST_SYSTEMD_ACTIVE SPARK_TEST_CLAUDE_STATUS
unset SPARK_TEST_CODEX_DAEMON_EXIT SPARK_TEST_CODEX_DAEMON_JSON SPARK_ASSUME_YES

fail() {
  printf 'sparkctl test: FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value=$1 expected=$2
  [[ "$value" == *"$expected"* ]] || fail "expected '$expected' in '$value'"
}

assert_file_contains() {
  local file=$1 expected=$2 contents
  contents=$(<"$file")
  assert_contains "$contents" "$expected"
}

# Mirrors the `printf '  %-16s %s\n'` layout doctor()/codex_status_lines use,
# so status-line assertions can't drift out of sync with a spacing typo here.
codex_line() {
  printf '  %-16s %s' "$1" "$2"
}

run_sparkctl() {
  env \
    XDG_CONFIG_HOME="$TEST_CONFIG_ROOT" \
    PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
    SPARK_PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
    SPARK_TEST_TMUX_LOG="$TEST_TMUX_LOG" \
    SPARK_TEST_CLAUDE_LOG="$TEST_CLAUDE_LOG" \
    SPARK_TEST_SYSTEMCTL_LOG="$TEST_SYSTEMCTL_LOG" \
    SPARK_TEST_CODEX_LOG="$TEST_CODEX_LOG" \
    CODEX_HOME="$TEST_CODEX_HOME" \
    SHELL=/bin/true \
    "$REPO_DIR/bin/sparkctl" "$@"
}

install -d "$TEST_CONFIG_ROOT" "$TEST_PROJECT_DIR" "$TEST_FAKE_BIN" "$TEST_CODEX_HOME"

cat >"$TEST_FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$SPARK_TEST_CLAUDE_LOG"
exit "${SPARK_TEST_CLAUDE_STATUS:-0}"
EOF

cat >"$TEST_FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SPARK_TEST_TMUX_LOG"
if [[ "${1:-}" == has-session ]]; then
  exit "${SPARK_TEST_TMUX_HAS_SESSION:-1}"
fi
EOF

cat >"$TEST_FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SPARK_TEST_SYSTEMCTL_LOG"
if [[ "$*" == '--user is-active --quiet '* ]]; then
  exit "${SPARK_TEST_SYSTEMD_ACTIVE:-1}"
fi
EOF

cat >"$TEST_FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SPARK_TEST_CODEX_LOG"
if [[ "$*" == 'app-server daemon version' ]]; then
  if [[ -n "${SPARK_TEST_CODEX_DAEMON_JSON:-}" ]]; then
    printf '%s\n' "$SPARK_TEST_CODEX_DAEMON_JSON"
  else
    printf '{"status":"running","appServerVersion":"9.9.9"}\n'
  fi
  exit "${SPARK_TEST_CODEX_DAEMON_EXIT:-0}"
fi
exit 0
EOF

chmod 0755 "$TEST_FAKE_BIN/claude" "$TEST_FAKE_BIN/systemctl" "$TEST_FAKE_BIN/tmux" "$TEST_FAKE_BIN/codex"

run_sparkctl project add legacy "$TEST_PROJECT_DIR" >/dev/null
assert_file_contains "$TEST_CONFIG_ROOT/spark-remote-control/projects/legacy.env" 'CLAUDE_SPAWN_MODE=same-dir'

run_sparkctl project add worktree "$REPO_DIR" --spawn worktree --capacity 4 >/dev/null
assert_file_contains "$TEST_CONFIG_ROOT/spark-remote-control/projects/worktree.env" 'CLAUDE_SPAWN_MODE=worktree'
assert_file_contains "$TEST_CONFIG_ROOT/spark-remote-control/projects/worktree.env" 'CLAUDE_CAPACITY=4'

if output=$(run_sparkctl project add one-shot "$TEST_PROJECT_DIR" --spawn session 2>&1); then
  fail "--spawn session unexpectedly succeeded"
fi
assert_contains "$output" 'use: sparkctl project tmux one-shot'

if output=$(run_sparkctl project add bad-capacity "$TEST_PROJECT_DIR" --capacity 0 2>&1); then
  fail "zero capacity unexpectedly succeeded"
fi
assert_contains "$output" '--capacity must be a positive integer'

if output=$(run_sparkctl project add non-git "$TEST_PROJECT_DIR" --spawn worktree 2>&1); then
  fail "worktree mode unexpectedly accepted a non-git directory"
fi
assert_contains "$output" 'to be a git repository'

run_sparkctl internal run-claude legacy
[[ "$(<"$TEST_CLAUDE_LOG")" == 'remote-control --permission-mode auto' ]] \
  || fail "legacy server arguments were not preserved"

run_sparkctl internal run-claude worktree
[[ "$(<"$TEST_CLAUDE_LOG")" == 'remote-control --permission-mode auto --spawn worktree --capacity 4' ]] \
  || fail "worktree server arguments were not forwarded"

cat >"$TEST_CONFIG_ROOT/spark-remote-control/projects/unsupported.env" <<EOF
CLAUDE_PROJECT_DIR=$TEST_PROJECT_DIR
CLAUDE_PERMISSION_MODE=auto
CLAUDE_SPAWN_MODE=session
EOF
if output=$(run_sparkctl internal run-claude unsupported 2>&1); then
  fail "a hand-written session-mode server config unexpectedly succeeded"
fi
assert_contains "$output" 'use: sparkctl project tmux unsupported'

: >"$TEST_TMUX_LOG"
run_sparkctl project tmux worktree
assert_file_contains "$TEST_TMUX_LOG" 'has-session -t =spark-claude-worktree'
assert_file_contains "$TEST_TMUX_LOG" "new-session -s spark-claude-worktree -c $REPO_DIR"
assert_file_contains "$TEST_TMUX_LOG" 'internal run-claude-tmux worktree'

if output=$(SPARK_TEST_SYSTEMD_ACTIVE=0 run_sparkctl project tmux worktree 2>&1); then
  fail "tmux workflow unexpectedly started beside the active service"
fi
assert_contains "$output" 'stop it before using: sparkctl project tmux worktree'

if output=$(SPARK_TEST_TMUX_HAS_SESSION=0 run_sparkctl project start worktree 2>&1); then
  fail "persistent service unexpectedly started beside the tmux workflow"
fi
assert_contains "$output" 'exit it before starting the persistent service for worktree'

: >"$TEST_TMUX_LOG"
SPARK_TEST_TMUX_HAS_SESSION=0 run_sparkctl project tmux worktree
assert_file_contains "$TEST_TMUX_LOG" 'attach-session -t =spark-claude-worktree'
if [[ "$(<"$TEST_TMUX_LOG")" == *'new-session'* ]]; then
  fail "an existing tmux session was started again"
fi

: >"$TEST_TMUX_LOG"
TMUX=fake SPARK_TEST_TMUX_HAS_SESSION=0 run_sparkctl project tmux worktree
assert_file_contains "$TEST_TMUX_LOG" 'switch-client -t =spark-claude-worktree'

: >"$TEST_TMUX_LOG"
TMUX=fake run_sparkctl project tmux worktree
assert_file_contains "$TEST_TMUX_LOG" 'new-session -d -s spark-claude-worktree'
assert_file_contains "$TEST_TMUX_LOG" 'switch-client -t =spark-claude-worktree'

output=$(SPARK_TEST_CLAUDE_STATUS=7 run_sparkctl internal run-claude-tmux worktree)
[[ "$(<"$TEST_CLAUDE_LOG")" == '--permission-mode auto --remote-control worktree' ]] \
  || fail "interactive Claude arguments were not forwarded"
assert_contains "$output" 'Claude exited with status 7; the tmux session remains open.'
assert_contains "$output" 'claude --continue'
assert_contains "$output" 'claude --resume'

output=$(run_sparkctl help)
assert_contains "$output" 'sparkctl codex <status|start|stop|enable|disable|restart|logs|pair|adopt>'

# codex_daemon_status via `sparkctl codex status`.
output=$(run_sparkctl codex status)
assert_contains "$output" "$(codex_line daemon 'running (9.9.9)')"

output=$(SPARK_TEST_CODEX_DAEMON_EXIT=1 run_sparkctl codex status)
assert_contains "$output" "$(codex_line daemon stopped)"

output=$(SPARK_TEST_CODEX_DAEMON_JSON='{"backend":"pid"}' run_sparkctl codex status)
assert_contains "$output" "$(codex_line daemon unknown)"

mv "$TEST_FAKE_BIN/codex" "$TEST_FAKE_BIN/codex.hidden"
output=$(run_sparkctl codex status)
assert_contains "$output" "$(codex_line daemon unknown)"
mv "$TEST_FAKE_BIN/codex.hidden" "$TEST_FAKE_BIN/codex"

# codex_remote_control_enabled reads $CODEX_HOME/app-server-daemon/settings.json.
install -d "$TEST_CODEX_HOME/app-server-daemon"
printf '{"remoteControlEnabled": true}' >"$TEST_CODEX_HOME/app-server-daemon/settings.json"
output=$(run_sparkctl codex status)
assert_contains "$output" "$(codex_line remote-control enabled)"

printf '{"remoteControlEnabled": false}' >"$TEST_CODEX_HOME/app-server-daemon/settings.json"
output=$(run_sparkctl codex status)
assert_contains "$output" "$(codex_line remote-control disabled)"

rm -f "$TEST_CODEX_HOME/app-server-daemon/settings.json"
output=$(run_sparkctl codex status)
assert_contains "$output" "$(codex_line remote-control unknown)"

# codex_guard_running_daemon: with the fake codex reporting a running daemon
# (the default) and the fake systemctl reporting the unit inactive (also the
# default), start/enable/restart must all refuse rather than reach systemctl.
: >"$TEST_SYSTEMCTL_LOG"
if output=$(run_sparkctl codex start 2>&1); then
  fail "codex start unexpectedly succeeded despite an unmanaged running daemon"
fi
assert_contains "$output" 'sparkctl codex adopt'
[[ "$(<"$TEST_SYSTEMCTL_LOG")" == '--user is-active --quiet spark-codex-remote.service' ]] \
  || fail "codex start guard reached systemctl beyond the is-active probe"

: >"$TEST_SYSTEMCTL_LOG"
if output=$(run_sparkctl codex enable 2>&1); then
  fail "codex enable unexpectedly succeeded despite an unmanaged running daemon"
fi
assert_contains "$output" 'sparkctl codex adopt'
[[ "$(<"$TEST_SYSTEMCTL_LOG")" == '--user is-active --quiet spark-codex-remote.service' ]] \
  || fail "codex enable guard reached systemctl beyond the is-active probe"

: >"$TEST_SYSTEMCTL_LOG"
if output=$(run_sparkctl codex restart 2>&1); then
  fail "codex restart unexpectedly succeeded despite an unmanaged running daemon"
fi
assert_contains "$output" 'sparkctl codex adopt'
[[ "$(<"$TEST_SYSTEMCTL_LOG")" == '--user is-active --quiet spark-codex-remote.service' ]] \
  || fail "codex restart guard reached systemctl beyond the is-active probe"

# The guard must not fire when the unit is already active...
: >"$TEST_SYSTEMCTL_LOG"
SPARK_TEST_SYSTEMD_ACTIVE=0 run_sparkctl codex restart
assert_file_contains "$TEST_SYSTEMCTL_LOG" '--user restart spark-codex-remote.service'

# ...nor when the daemon is not running, regardless of unit state.
: >"$TEST_SYSTEMCTL_LOG"
SPARK_TEST_CODEX_DAEMON_EXIT=1 run_sparkctl codex enable
assert_file_contains "$TEST_SYSTEMCTL_LOG" '--user enable --now spark-codex-remote.service'

# stop/disable are never guarded, even when a running daemon would otherwise
# trigger the refusal for start/enable/restart.
: >"$TEST_SYSTEMCTL_LOG"
run_sparkctl codex stop
[[ "$(<"$TEST_SYSTEMCTL_LOG")" == '--user stop spark-codex-remote.service' ]] \
  || fail "codex stop should reach systemctl directly without the running-daemon guard"

: >"$TEST_SYSTEMCTL_LOG"
run_sparkctl codex disable
[[ "$(<"$TEST_SYSTEMCTL_LOG")" == '--user disable --now spark-codex-remote.service' ]] \
  || fail "codex disable should reach systemctl directly without the running-daemon guard"

# codex adopt with SPARK_ASSUME_YES=1 stops the running daemon, then enables
# the unit. Route both fakes' logs to one file so the ordering is checkable.
: >"$TEST_ROOT/adopt-order.log"
env \
  XDG_CONFIG_HOME="$TEST_CONFIG_ROOT" \
  PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
  SPARK_PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
  SPARK_TEST_TMUX_LOG="$TEST_TMUX_LOG" \
  SPARK_TEST_CLAUDE_LOG="$TEST_CLAUDE_LOG" \
  SPARK_TEST_SYSTEMCTL_LOG="$TEST_ROOT/adopt-order.log" \
  SPARK_TEST_CODEX_LOG="$TEST_ROOT/adopt-order.log" \
  CODEX_HOME="$TEST_CODEX_HOME" \
  SPARK_ASSUME_YES=1 \
  SHELL=/bin/true \
  "$REPO_DIR/bin/sparkctl" codex adopt

mapfile -t adopt_order_lines <"$TEST_ROOT/adopt-order.log"
[[ "${adopt_order_lines[0]:-}" == 'remote-control stop' ]] \
  || fail "adopt did not stop the running daemon"
[[ "${adopt_order_lines[1]:-}" == '--user enable --now spark-codex-remote.service' ]] \
  || fail "adopt did not enable the unit after stopping the daemon, or ran them out of order"

# Without SPARK_ASSUME_YES and without a TTY, adopt must refuse rather than
# prompt or act.
if output=$(run_sparkctl codex adopt </dev/null 2>&1); then
  fail "codex adopt without confirmation unexpectedly succeeded"
fi
assert_contains "$output" 'refusing to adopt'

# The internal runners invoked by the unit itself.
: >"$TEST_CODEX_LOG"
run_sparkctl internal run-codex-start
[[ "$(<"$TEST_CODEX_LOG")" == 'remote-control start' ]] \
  || fail "run-codex-start did not exec codex remote-control start"

: >"$TEST_CODEX_LOG"
run_sparkctl internal run-codex-stop
[[ "$(<"$TEST_CODEX_LOG")" == 'remote-control stop' ]] \
  || fail "run-codex-stop did not exec codex remote-control stop"

if output=$(run_sparkctl codex badaction 2>&1); then
  fail "unknown codex action unexpectedly succeeded"
fi
assert_contains "$output" 'unknown codex action: badaction'

printf 'sparkctl smoke tests: PASS\n'
