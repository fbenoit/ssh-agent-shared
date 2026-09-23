# ssh-agent-shared

One ssh-agent per machine, shared by every terminal, plus small auth scripts
that load the right keys for each personal repository.

Terms used below are defined in [CONTEXT.md](CONTEXT.md). Design decisions are
in [docs/design.md](docs/design.md).

## Contents

| Path | Role |
| --- | --- |
| `bin/_ssh-agent-shared.sh` | Helper sourced by every auth script: starts or reuses the shared agent on `~/.ssh/agent.sock` and defines `ssh_agent_ensure` and `ssh_github_check`. |
| `bin/sas-auth` | Auth script for this repository. |
| `templates/auth-script.sh` | Template for a new auth script. |
| `ssh_config.d/*.conf` | Host aliases, one per repository. |
| `gitconfig-personal` | Personal git identity and SSH commit signing for every repository under `~/Personal/`. |
| `allowed_signers` | Public signing keys of every machine, used to verify commits. |
| `install.sh` | Creates or removes the symlinks, also for the private overlay. |
| `tests/run.sh` | Integration tests in bash and zsh, in a throwaway `HOME`. |

## Set up a new machine

Replace `<machine>` with a short machine name, for example `home-linux`. Set a
passphrase for each key when prompted. The steps need `git`, `curl` and `jq`.

1. Trust GitHub's SSH host keys, so the first connection does not ask:

   ```
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
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
   ssh-keygen -t ed25519 -C "<repo>-<machine>" -f ~/.ssh/<repo>_ed25519
   ssh-keygen -t ed25519 -C "ssh-agent-shared-<machine>" -f ~/.ssh/ssh_agent_shared_ed25519
   ```

   For private repositories, also create the
   [private overlay](#private-repositories) now: `install.sh` links its
   scripts in the next step.

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
     Include ~/.config/ssh-agent-shared/ssh_config.d/*.conf
     ```

     The second line is for the private overlay. It does nothing while the
     overlay does not exist.

   - `~/.ssh/config`, so that ssh never offers a deploy key to the wrong
     repository. Add a `github.com` block, and a `Host *` block as the last
     block of the file:

     ```
     Host github.com
         IdentityFile none
         IdentitiesOnly yes

     Host *
         IdentitiesOnly yes
     ```

     Also remove any global `AddKeysToAgent yes`: keys must enter the agent
     only through the auth scripts, which load them with a lifetime. With this
     config, `ssh -T git@github.com` fails with "Permission denied
     (publickey)", which is expected. Every repository reaches GitHub through
     its own host alias, or over HTTPS.

7. Load the keys and test the connections: `sas-auth`, then the auth script
   of each other repository.

8. Add this machine's signing key to `allowed_signers`, switch the remote to
   the host alias, and push:

   ```
   echo "1279695+fbenoit@users.noreply.github.com namespaces=\"git\" $(cat ~/.ssh/personal_signing_ed25519.pub)" >> allowed_signers
   git remote set-url origin git@github-ssh-agent-shared:fbenoit/ssh-agent-shared.git
   git commit -am "chore: add <machine> signing key"
   git push
   ```

   On a machine without the `ssh-agent-shared` deploy key, this push is not
   possible. Copy the line into `allowed_signers` from a machine that can push.
   Until then, other machines show "No principal matched" for this machine's
   commits in `git log --show-signature`; GitHub still shows them as Verified.

## Use

Run the auth script of a repository before you work in it, and again after a
reboot or when the keys expire:

```
sas-auth
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

After a pull, run `./install.sh` again: it links new scripts and removes links
to deleted ones. Before pulling the commit that moved the private repository
files out of this repository, copy them into the private overlay (see below),
or the pull deletes them from this machine too.

## Add a personal repository

Identity and signing need nothing per repository: any clone under
`~/Personal/` gets them from `~/.gitconfig-personal`. Only push access is per
repository.

For a public repository that you only read, clone over HTTPS and stop there.
Otherwise, give it a deploy key, a host alias and an auth script:

1. Create the deploy key and register it at
   `https://github.com/fbenoit/<name>/settings/keys`, title `<name>-<machine>`,
   with **Allow write access**:

   ```
   ssh-keygen -t ed25519 -C "<name>-<machine>" -f ~/.ssh/<name>_ed25519
   ```

2. Add `ssh_config.d/<name>.conf` with the host alias (for a private
   repository, see [Private repositories](#private-repositories)):

   ```
   Host github-<name>
       HostName github.com
       User git
       IdentityFile ~/.ssh/<name>_ed25519
       IdentitiesOnly yes
   ```

3. Copy the template: `cp templates/auth-script.sh bin/<short-name>-auth`.
   Replace `__REPO__`, `__SHORT_NAME__`, `__DEPLOY_KEY__` and `__HOST_ALIAS__`.
4. Run `./install.sh` to link the new script, then run it.
5. Clone through the alias, under `~/Personal/`:

   ```
   git clone git@github-<name>:fbenoit/<name>.git ~/Personal/<name>
   ```

   For an existing clone, switch its remote instead:
   `git remote set-url origin git@github-<name>:fbenoit/<name>.git`.
6. Commit and push the new files in this repository.

This repository is public: the alias and the auth script reveal the
repository name. Keep the files of private repositories in the private
overlay instead.

Keep the rules written at the top of the template: a sourced script runs in
your own shell, so it must never call `exit` on its own, `set -e`, `set -u` or
`trap`, and must not set top-level variables.

## Private repositories

The names of private repositories stay out of this public repository. Their
host aliases and auth scripts live in the private overlay, a local directory
that is never committed:

```
~/.config/ssh-agent-shared/          ($XDG_CONFIG_HOME/ssh-agent-shared if set)
    bin/<short-name>-auth
    ssh_config.d/<name>.conf
```

`install.sh` links `bin/*` from the overlay into `~/.local/bin`, like the
scripts of this repository, and prints the `Include` line for its
`ssh_config.d` when it is missing from `~/.ssh/config`. An overlay script with
the name of a script in this repository is skipped with a warning.

To add a private repository, follow [Add a personal
repository](#add-a-personal-repository), but write the alias to
`~/.config/ssh-agent-shared/ssh_config.d/<name>.conf` and copy the template to
`~/.config/ssh-agent-shared/bin/<short-name>-auth`. Skip the commit step.

On a new machine, copy the overlay from a machine that has it, or recreate
each file from the template. The private repository itself can document its
alias and auth script, for example in its setup notes.

CI rejects the names of private repositories with the `no-private-names`
job. It reads an extended regular expression from the repository secret
`PRIVATE_NAMES_REGEX`, prints only the names of matching files, and does
nothing when the secret is not set. Add each new private repository name to
the secret.

## Work accounts

Scripts for work accounts do not belong in this public repository. Keep them
in `~/.local/bin` only; they can source `~/.local/bin/_ssh-agent-shared.sh`
like the scripts here.

## Uninstall

```
./install.sh --uninstall
```

It removes only the symlinks that point into this repository or the private
overlay, and restores the latest `.bak.<timestamp>` backup of each file.
Restored files are the versions from before the install and may use old key
names. The helper is replaced by a copy rather than removed, because local
scripts may still source it. Remove the lines you added by hand in step 6.

## Development

```
tests/run.sh
shellcheck -x bin/_ssh-agent-shared.sh bin/*-auth templates/auth-script.sh install.sh tests/run.sh
```

CI runs both on every push, and also rejects employer or work-script names.
