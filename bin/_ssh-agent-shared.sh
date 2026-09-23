#!/usr/bin/env bash
# shellcheck shell=bash
# Shared ssh-agent helper for auth scripts.
#
# Makes every terminal (tabs, panes, multiplexers) reuse one ssh-agent bound
# to a fixed socket, instead of one agent per terminal.
#
# Source it from bash or zsh, never execute it:
#   source ~/.local/bin/_ssh-agent-shared.sh
#
# This file runs inside the user's interactive shell. Rules:
#   - no set -e, set -u or trap: they would change or kill the user's shell;
#   - every function-scoped variable is declared local;
#   - no top-level variable except the exported SSH_AUTH_SOCK.

export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

# _sas_agent_alive: success when an agent answers on the socket.
# ssh-add -l exits 0 (keys loaded), 1 (no keys) or 2 (no agent).
_sas_agent_alive() {
  ssh-add -l >/dev/null 2>&1
  [ "$?" -ne 2 ]
}

# _sas_agent_start: start the shared agent unless one already answers.
# The lock stops two terminals from starting two agents at the same time.
_sas_agent_start() {
  _sas_agent_alive && return 0
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  (
    command -v flock >/dev/null 2>&1 && flock 9
    if ! _sas_agent_alive; then
      rm -f "$SSH_AUTH_SOCK"
      ssh-agent -a "$SSH_AUTH_SOCK" >/dev/null
    fi
  ) 9>"$HOME/.ssh/agent.lock"
}

# ssh_agent_ensure <private-key-path>
# Loads the key into the shared agent unless it is already there, so sourcing
# an auth script again does not ask for the passphrase again.
# Keys expire after SSH_AGENT_SHARED_LIFETIME (default 12h).
ssh_agent_ensure() {
  local key="$1" fp
  if [ ! -f "$key" ]; then
    echo "key not found: $key" >&2
    return 1
  fi
  if [ ! -f "$key.pub" ]; then
    echo "public key not found: $key.pub" >&2
    return 1
  fi
  fp=$(ssh-keygen -lf "$key.pub" 2>/dev/null | awk '{print $2}')
  if [ -z "$fp" ]; then
    echo "cannot read fingerprint: $key.pub" >&2
    return 1
  fi
  if ssh-add -l 2>/dev/null | grep -qF -- "$fp"; then
    return 0
  fi
  ssh-add -t "${SSH_AGENT_SHARED_LIFETIME:-12h}" "$key"
}

# ssh_github_check <host-alias>
# Tests the connection to GitHub through an ~/.ssh/config alias.
# ssh -T exits 1 even on success with GitHub, so success is read from the
# greeting instead.
ssh_github_check() {
  local out
  out=$(ssh -T "$1" 2>&1)
  printf '%s\n' "$out"
  case "$out" in
    *"successfully authenticated"*) return 0 ;;
  esac
  return 1
}

_sas_agent_start
