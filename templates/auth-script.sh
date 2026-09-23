#!/usr/bin/env bash
# shellcheck shell=bash
# Auth script template. Copy it to bin/__SHORT_NAME__-auth, then replace:
#   __REPO__        the GitHub repository, for example fbenoit/learnings
#   __SHORT_NAME__  the script name prefix, for example lrn
#   __DEPLOY_KEY__  the deploy key file name in ~/.ssh, for example learnings_ed25519
#   __HOST_ALIAS__  the Host alias in ssh_config.d/, for example github-learnings
#
# Auth script for __REPO__: load the deploy key and the personal signing key
# into the shared agent, then test the connection.
#
# Usage: __SHORT_NAME__-auth
#    or: source ~/.local/bin/__SHORT_NAME__-auth
#
# Keep these rules, because a sourced script runs in the user's shell:
#   - end each failing step with: || return 1 2>/dev/null || exit 1
#     (return when sourced, exit when executed);
#   - no set -e, set -u, trap or exit on its own;
#   - no top-level variables (zsh reserves names such as path, status, argv).

# shellcheck source=bin/_ssh-agent-shared.sh
source ~/.local/bin/_ssh-agent-shared.sh || return 1 2>/dev/null || exit 1

ssh_agent_ensure ~/.ssh/__DEPLOY_KEY__ || return 1 2>/dev/null || exit 1
ssh_agent_ensure ~/.ssh/personal_signing_ed25519 || return 1 2>/dev/null || exit 1
ssh_github_check __HOST_ALIAS__
