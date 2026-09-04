#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PROFILE_SOURCE="$REPO_DIR/config/apparmor/bwrap-userns-restrict"
readonly PROFILE_TARGET=/etc/apparmor.d/bwrap-userns-restrict
readonly PROFILE_SHA256=95a294671635b96eb64369007a8a3a1ee84917cbeae37351a145e337a8d75c9b
readonly MANAGED_MARKER='Managed by spark-remote-control'
readonly STATE_DIR=/var/lib/spark-remote-control
readonly STATE_FILE="$STATE_DIR/bwrap-userns-restrict.sha256"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: bwrap-apparmor.sh <status|install|remove|test>

Installs Ubuntu's stacked AppArmor profile for /usr/bin/bwrap. It does not
disable Ubuntu's user-namespace restriction globally, make bwrap setuid, or
overwrite a profile it cannot prove it owns.
EOF
}

checksum() {
  local digest _
  read -r digest _ < <(sha256sum "$1")
  printf '%s\n' "$digest"
}

source_is_valid() {
  [[ -f "$PROFILE_SOURCE" && "$(checksum "$PROFILE_SOURCE")" == "$PROFILE_SHA256" ]]
}

target_is_managed() {
  [[ -f "$PROFILE_TARGET" && -r "$STATE_FILE" ]] || return 1
  grep -Fq "$MANAGED_MARKER" "$PROFILE_TARGET" || return 1
  [[ "$(checksum "$PROFILE_TARGET")" == "$(<"$STATE_FILE")" ]]
}

read_sysctl() {
  local name=$1 path="/proc/sys/${1//./\/}"
  if [[ -r "$path" ]]; then
    printf '%s=%s\n' "$name" "$(<"$path")"
  else
    printf '%s=%s\n' "$name" unavailable
  fi
}

test_bwrap() {
  have bwrap || die "bubblewrap is not installed"
  bwrap --die-with-parent --new-session \
    --unshare-user --unshare-pid --unshare-net \
    --uid 0 --gid 0 \
    --ro-bind / / --proc /proc --dev /dev \
    /bin/true
}

status() {
  if have bwrap; then
    say "bwrap=$(command -v bwrap)"
    bwrap --version
  else
    say "bwrap=missing"
  fi
  read_sysctl kernel.unprivileged_userns_clone
  read_sysctl user.max_user_namespaces
  read_sysctl kernel.apparmor_restrict_unprivileged_userns
  source_is_valid && say "profile_source=verified" || say "profile_source=invalid"
  if target_is_managed; then
    say "apparmor_profile=managed"
  elif [[ -f "$PROFILE_TARGET" ]]; then
    say "apparmor_profile=unmanaged-or-modified"
  else
    say "apparmor_profile=missing"
  fi
  if test_bwrap >/dev/null 2>&1; then
    say "sandbox_test=pass"
  else
    say "sandbox_test=fail"
  fi
}

install_profile() {
  source_is_valid || die "vendored profile checksum mismatch; refusing to install"
  have apparmor_parser || die "apparmor_parser is missing; install the apparmor package"

  if [[ -e "$PROFILE_TARGET" ]] && ! target_is_managed && ! cmp -s "$PROFILE_SOURCE" "$PROFILE_TARGET"; then
    die "refusing to overwrite an untracked or modified profile: $PROFILE_TARGET"
  fi

  # Validate as the current user without loading policy or writing parser cache.
  apparmor_parser -Q -K "$PROFILE_SOURCE"
  sudo -v

  local state_temp
  state_temp=$(mktemp)
  trap 'rm -f "$state_temp"' EXIT
  printf '%s\n' "$PROFILE_SHA256" >"$state_temp"

  sudo install -o root -g root -m 0644 "$PROFILE_SOURCE" "$PROFILE_TARGET"
  sudo apparmor_parser -r "$PROFILE_TARGET"
  sudo install -d -o root -g root -m 0755 "$STATE_DIR"
  sudo install -o root -g root -m 0644 "$state_temp" "$STATE_FILE"
  say "Installed and loaded $PROFILE_TARGET"

  if test_bwrap; then
    say "Bubblewrap namespace test passed. Restart Codex."
  else
    die "profile loaded, but the namespace test still fails; inspect 'journalctl -k'"
  fi
}

remove_profile() {
  [[ -e "$PROFILE_TARGET" ]] || { say "No managed profile is installed."; return; }
  target_is_managed || die "refusing to remove an untracked or modified profile: $PROFILE_TARGET"
  sudo -v
  local disabled_dir=/etc/apparmor.d/disable
  local timestamp disabled_target disabled_state
  timestamp=$(date +%Y%m%d%H%M%S)
  disabled_target="$disabled_dir/bwrap-userns-restrict.spark-disabled-$timestamp"
  disabled_state="$disabled_target.sha256"
  sudo apparmor_parser -R "$PROFILE_TARGET"
  sudo install -d -o root -g root -m 0755 "$disabled_dir"
  sudo mv "$PROFILE_TARGET" "$disabled_target"
  sudo mv "$STATE_FILE" "$disabled_state"
  say "Disabled profile and preserved it at $disabled_target"
}

case "${1:-}" in
  status) status ;;
  install) install_profile ;;
  remove) remove_profile ;;
  test) test_bwrap && say "Bubblewrap namespace test passed." ;;
  help|-h|--help|'') usage ;;
  *) die "unknown command: $1" ;;
esac

