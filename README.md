# ssh-agent-shared

One ssh-agent per machine, shared by every terminal, plus small auth scripts
that load the right keys for each personal repository.

Terms used below are defined in [CONTEXT.md](CONTEXT.md). Design decisions are
in [docs/design.md](docs/design.md).

## Contents

| Path | Role |
| --- | --- |
| `bin/_ssh-agent-shared.sh` | Helper sourced by every auth script: starts or reuses the shared agent on `~/.ssh/agent.sock` and defines `ssh_agent_ensure` and `ssh_github_check`. |
| `bin/lrn-auth`, `bin/sb-auth`, `bin/sas-auth` | Auth scripts for `learnings`, `second_brain` and this repository. |
| `templates/auth-script.sh` | Template for a new auth script. |
| `ssh_config.d/*.conf` | Host aliases, one per repository. |
| `gitconfig-personal` | Personal git identity and SSH commit signing for every repository under `~/Personal/`. |
| `allowed_signers` | Public signing keys of every machine, used to verify commits. |
| `install.sh` | Creates or removes the symlinks. |
| `tests/run.sh` | Integration tests in bash and zsh, in a throwaway `HOME`. |

## Set up a new machine

Replace `<machine>` with a short machine name, for example `home-linux`. Set a
passphrase for each key when prompted. The steps need `git`, `curl` and `jq`.

1. Trust GitHub's SSH host keys, so the first connection does not ask:

   ```
   curl -s https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' >> ~/.ssh/known_hosts
   ```

2. Clone over HTTPS. The repository is public, so no key is needed yet:

   ```
   git clone https://github.com/fbenoit/ssh-agent-shared.git ~/Personal/ssh-agent-shared
   cd ~/Personal/ssh-agent-shared
   ```

3. Check that the last commit was signed by one of the account's signing keys.
   Compare the fingerprint printed by the first command with the list printed
   by the second:

   ```
   git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=allowed_signers verify-commit HEAD
   curl -s https://api.github.com/users/fbenoit/ssh_signing_keys | jq -r '.[].key' | ssh-keygen -lf -
   ```

4. Create the personal signing key, and a deploy key for each repository you
   use on this machine. The `ssh-agent-shared` deploy key is only needed if you
   edit this repository on this machine.

   ```
   ssh-keygen -t ed25519 -C "personal-signing-<machine>" -f ~/.ssh/personal_signing_ed25519
   ssh-keygen -t ed25519 -C "learnings-<machine>" -f ~/.ssh/learnings_ed25519
   ssh-keygen -t ed25519 -C "ssh-agent-shared-<machine>" -f ~/.ssh/ssh_agent_shared_ed25519
   ```

5. Register the keys on github.com:
   - Personal signing key: `https://github.com/settings/ssh/new`, key type
     **Signing Key**, title `personal-signing-<machine>`.
   - Each deploy key: `https://github.com/fbenoit/<repo>/settings/keys`, title
     `<repo>-<machine>`, tick **Allow write access**.

6. Run the installer:

   ```
   ./install.sh
   ```

   It prints the lines that are still missing from your own files. Add them by
   hand:
   - `~/.zshrc` or `~/.bashrc`: `export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"`.
     On a machine where you also log in over SSH with agent forwarding, or where
     a desktop keyring provides an agent, use
     `[ -z "$SSH_CONNECTION" ] && export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"`
     and disable the desktop agent's SSH component.
   - `~/.gitconfig`:

     ```
     [includeIf "gitdir:~/Personal/"]
         path = ~/.gitconfig-personal
     ```

   - `~/.ssh/config`, at the top of the file (an `Include` placed after a
     `Host` line only applies to that host):

     ```
     Include ~/Personal/ssh-agent-shared/ssh_config.d/*.conf
     ```

7. Load the keys and test the connections: `sas-auth`, `lrn-auth`.

8. Add this machine's signing key to `allowed_signers`, switch the remote to
   the host alias, and push:

   ```
   echo "1279695+fbenoit@users.noreply.github.com namespaces=\"git\" $(cat ~/.ssh/personal_signing_ed25519.pub)" >> allowed_signers
   git remote set-url origin git@github-ssh-agent-shared:fbenoit/ssh-agent-shared.git
   git commit -am "chore: add <machine> signing key"
   git push
   ```

## Use

Run the auth script of a repository before you work in it, and again after a
reboot or when the keys expire:

```
lrn-auth
```

Auth scripts can be executed or sourced. Executing is enough when your shell
rc file exports `SSH_AUTH_SOCK` (step 6). Keys stay loaded for
`SSH_AGENT_SHARED_LIFETIME`, 12 hours by default:

```
export SSH_AGENT_SHARED_LIFETIME=8h
```

A successful auth script prints GitHub's greeting and returns 0. A missing key
prints `key not found: <path>` and returns 1 without running the connection
test.

## Update

This code runs in shells that can use every key in the shared agent. Update
only to commits signed by a known key, and read the changes first:

```
cd ~/Personal/ssh-agent-shared
git fetch
git log -p HEAD..origin/main
git pull --ff-only --verify-signatures
```

The `main` branch on GitHub requires signed commits.

## Add an auth script

1. Copy the template: `cp templates/auth-script.sh bin/<short-name>-auth`.
2. Replace `__REPO__`, `__SHORT_NAME__`, `__DEPLOY_KEY__` and `__HOST_ALIAS__`.
3. Add `ssh_config.d/<name>.conf` with the host alias:

   ```
   Host github-<name>
       HostName github.com
       User git
       IdentityFile ~/.ssh/<name>_ed25519
       IdentitiesOnly yes
   ```

4. Run `./install.sh` to link the new script.

Keep the rules written at the top of the template: a sourced script runs in
your own shell, so it must never call `exit` on its own, `set -e`, `set -u` or
`trap`, and must not set top-level variables.

Scripts for work accounts do not belong in this public repository. Keep them
in `~/.local/bin` only; they can source `~/.local/bin/_ssh-agent-shared.sh`
like the scripts here.

## Uninstall

```
./install.sh --uninstall
```

It removes only the symlinks that point into this repository and restores the
latest `.bak.<timestamp>` backup of each file. Restored files are the versions
from before the install and may use old key names. The helper is replaced by a
copy rather than removed, because local scripts may still source it. Remove
the lines you added by hand in step 6.

## Development

```
tests/run.sh
shellcheck -x bin/_ssh-agent-shared.sh bin/*-auth templates/auth-script.sh install.sh tests/run.sh
```

CI runs both on every push, and also rejects employer or work-script names.
