# Design decisions

Agreed on 2026-09-23 and reviewed before implementation.

## Repository

- Public, cloned over HTTPS to `~/Personal/ssh-agent-shared`, so a new machine
  can clone it before any SSH key exists. It holds no secrets: only key file
  paths, host aliases and public keys.
- Holds the helper and the auth scripts of personal repositories only. Scripts
  for work accounts stay local on each machine; they source the same helper
  path, so the helper keeps its name `~/.local/bin/_ssh-agent-shared.sh`.
- Holds no names of private repositories. Their host aliases and auth scripts
  live in the private overlay, `${XDG_CONFIG_HOME:-~/.config}/ssh-agent-shared`,
  a local directory with the same `bin/` and `ssh_config.d/` layout. The
  overlay is not synced: a new machine copies it or recreates it from the
  template. The names published before this rule stay in the git history;
  the history is not rewritten.
- CI rejects private repository names and work names with regular
  expressions kept in the repository secrets `PRIVATE_NAMES_REGEX` and
  `WORK_NAMES_REGEX`, so the checks do not publish the names. They print file
  names only, never matching lines. Names published before this rule stay in
  the git history.
- Push access uses a deploy key per machine and the `github-ssh-agent-shared`
  host alias, only on machines that edit the repository.
- The `main` branch requires signed commits. Updates use
  `git pull --ff-only --verify-signatures`; nothing updates automatically,
  because the helper runs in shells that can use every key in the agent.

## Installation

- `install.sh` symlinks files into `$HOME`, so `git pull` updates them.
- It also links `bin/*` from the private overlay when it exists. An overlay
  script with the name of a repository script is skipped.
- It removes dangling links into the repository or the overlay, left by
  deleted or moved scripts.
- It is idempotent. A regular file or a foreign symlink in the way is renamed
  `<name>.bak.<timestamp>`; a directory stops the install. Links are created
  atomically.
- It never edits `~/.zshrc`, `~/.gitconfig` or `~/.ssh/config`. It prints the
  missing lines instead.
- `--uninstall` removes only links into the repository or the overlay, and
  restores the latest backup. The helper is replaced by a copy, because local
  scripts may still source it.

## Scripts

- The helper and auth scripts run sourced in bash and zsh, or executed. The
  shell rc file exports `SSH_AUTH_SOCK`, so executing is enough.
- Sourced code never uses `set -e`, `set -u`, `trap` or a bare `exit`, and sets
  no top-level variables other than `SSH_AUTH_SOCK`. Each failing step ends
  with `|| return 1 2>/dev/null || exit 1`.
- A missing private or public key prints a clear error and stops the auth
  script before the connection test.
- The connection test succeeds on GitHub's greeting, because `ssh -T` exits 1
  even on success.
- Keys are loaded with a lifetime, `SSH_AGENT_SHARED_LIFETIME`, 12 hours by
  default.
- A lock stops two terminals from starting two agents at the same time.

## Identity and signing

- Every repository under `~/Personal/` gets the personal identity through
  `includeIf "gitdir:~/Personal/"` in `~/.gitconfig`, so a new clone cannot
  commit with the global (work) identity by mistake.
- Each machine has one personal signing key, registered on the GitHub account,
  that signs commits in all personal repositories. Deploy keys stay one per
  repository per machine.
- `allowed_signers` in this repository lists the signing keys of every
  machine, so commits from any machine verify on all of them. Retired keys stay
  listed, so old commits still verify.
- Every auth script of a personal repository loads its deploy key and the
  personal signing key.

## Out of scope

- Hardening of `~/.ssh/config` (a `Host github.com` block, the global
  `AddKeysToAgent` setting).
- Cleanup of old keys committed to another repository.
