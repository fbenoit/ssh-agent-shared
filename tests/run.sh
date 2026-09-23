#!/usr/bin/env bash
# Integration tests. They run against a throwaway HOME and a throwaway agent,
# so they never touch the real ~/.ssh, ~/.local/bin or agent.
#
# Usage: tests/run.sh

# Snippets in single quotes run in child shells, where $HOME must expand.
# shellcheck disable=SC2016
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP_HOME=$(mktemp -d)
export HOME="$TMP_HOME"
unset SSH_AUTH_SOCK SSH_AGENT_PID
failures=0

cleanup() {
  pkill -f "ssh-agent -a $TMP_HOME/.ssh/agent.sock" 2>/dev/null || true
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

mkdir -p "$HOME/.ssh" "$HOME/.local/bin"
chmod 700 "$HOME/.ssh"

# A pre-existing regular file must be backed up by the install.
echo "old" > "$HOME/.local/bin/lrn-auth"

"$REPO/install.sh" >/dev/null 2>&1
check "install links the helper" test "$(readlink "$HOME/.local/bin/_ssh-agent-shared.sh")" = "$REPO/bin/_ssh-agent-shared.sh"
check "install links gitconfig-personal" test "$(readlink "$HOME/.gitconfig-personal")" = "$REPO/gitconfig-personal"
check "install backs up a regular file" sh -c 'ls "$HOME"/.local/bin/lrn-auth.bak.* >/dev/null 2>&1'

"$REPO/install.sh" >/dev/null 2>&1
check "second install creates no new backup" test "$(find "$HOME/.local/bin" -name 'lrn-auth.bak.*' | wc -l)" -eq 1

# Keys without passphrase, so ssh-add does not prompt.
ssh-keygen -q -t ed25519 -N '' -C test -f "$HOME/.ssh/learnings_ed25519"
ssh-keygen -q -t ed25519 -N '' -C test -f "$HOME/.ssh/personal_signing_ed25519"
fp=$(ssh-keygen -lf "$HOME/.ssh/learnings_ed25519.pub" | awk '{print $2}')

for sh in bash zsh; do
  if ! command -v "$sh" >/dev/null 2>&1; then
    echo "SKIP $sh not installed"
    continue
  fi

  check "$sh: helper starts the agent and loads a key" "$sh" -c '
    source ~/.local/bin/_ssh-agent-shared.sh
    ssh_agent_ensure ~/.ssh/learnings_ed25519 2>/dev/null
    ssh-add -l | grep -qF -- "'"$fp"'"'

  check "$sh: second ensure does not call ssh-add" "$sh" -c '
    source ~/.local/bin/_ssh-agent-shared.sh
    ssh-add() {
      if [ "$1" = -l ]; then command ssh-add -l; else echo called; return 1; fi
    }
    ssh_agent_ensure ~/.ssh/learnings_ed25519'

  check "$sh: missing key fails without killing the shell" "$sh" -c '
    source ~/.local/bin/sb-auth 2>/dev/null
    rc=$?
    [ "$rc" -eq 1 ]'

  check "$sh: missing key prints a clear message" "$sh" -c '
    source ~/.local/bin/sb-auth 2>&1 | grep -qF "key not found: $HOME/.ssh/second_brain_ed25519"'
done

check "executed auth script exits 1 on missing key" sh -c '! "$HOME/.local/bin/sb-auth" 2>/dev/null'

"$REPO/install.sh" --uninstall >/dev/null 2>&1
check "uninstall keeps a copy of the helper" sh -c 'test -f "$HOME/.local/bin/_ssh-agent-shared.sh" && test ! -L "$HOME/.local/bin/_ssh-agent-shared.sh"'
check "uninstall restores the backup" test "$(cat "$HOME/.local/bin/lrn-auth")" = "old"
check "uninstall removes other links" test ! -e "$HOME/.local/bin/sas-auth"
check "uninstall removes gitconfig-personal" test ! -e "$HOME/.gitconfig-personal"

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
