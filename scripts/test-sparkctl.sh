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

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

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

run_sparkctl() {
  env \
    XDG_CONFIG_HOME="$TEST_CONFIG_ROOT" \
    PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
    SPARK_PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
    SPARK_TEST_TMUX_LOG="$TEST_TMUX_LOG" \
    SPARK_TEST_CLAUDE_LOG="$TEST_CLAUDE_LOG" \
    SPARK_TEST_SYSTEMCTL_LOG="$TEST_SYSTEMCTL_LOG" \
    SHELL=/bin/true \
    "$REPO_DIR/bin/sparkctl" "$@"
}

install -d "$TEST_CONFIG_ROOT" "$TEST_PROJECT_DIR" "$TEST_FAKE_BIN"

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

chmod 0755 "$TEST_FAKE_BIN/claude" "$TEST_FAKE_BIN/systemctl" "$TEST_FAKE_BIN/tmux"

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

printf 'sparkctl smoke tests: PASS\n'
