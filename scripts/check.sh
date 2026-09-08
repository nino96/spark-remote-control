#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

failed=0
while IFS= read -r script; do
  if bash -n "$script"; then
    printf 'bash -n: PASS %s\n' "${script#"$REPO_DIR/"}"
  else
    failed=1
  fi
done < <(find "$REPO_DIR/bin" "$REPO_DIR/scripts" -type f \( -name '*.sh' -o -name 'sparkctl' \) ! -name '*.next' | sort)

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t scripts < <(find "$REPO_DIR/bin" "$REPO_DIR/scripts" -type f \( -name '*.sh' -o -name 'sparkctl' \) ! -name '*.next' | sort)
  shellcheck "${scripts[@]}"
  printf 'shellcheck: PASS\n'
else
  printf 'shellcheck: SKIP (not installed)\n'
fi

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze --user verify "$REPO_DIR"/systemd/user/*.service
  printf 'systemd units: PASS\n'
else
  printf 'systemd units: SKIP (systemd-analyze not installed)\n'
fi

if command -v apparmor_parser >/dev/null 2>&1; then
  apparmor_parser -Q -K "$REPO_DIR/config/apparmor/bwrap-userns-restrict"
  printf 'AppArmor profile: PASS\n'
else
  printf 'AppArmor profile: SKIP (apparmor_parser not installed)\n'
fi

"$REPO_DIR/scripts/test-sparkctl.sh"

exit "$failed"
