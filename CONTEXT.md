# ssh-agent-shared

Tools and conventions that give every terminal on a machine access to the same
SSH keys, for pushing to and signing commits in personal repositories.

## Language

**Shared agent**:
The single ssh-agent of a machine, reached through the fixed socket
`~/.ssh/agent.sock`, that every terminal uses.
_Avoid_: agent (alone), per-terminal agent

**Auth script**:
A script that loads the keys of one target into the shared agent and may then
test the connection to that target. It can be sourced or executed.
_Avoid_: login script, sign script

**Deploy key**:
An SSH key that gives one machine access to one GitHub repository only, used
for push and pull.
_Avoid_: repo key, access key

**Personal signing key**:
The SSH key of one machine that signs commits in all personal repositories. It
is registered on the GitHub account as a Signing Key.
_Avoid_: GPG key, commit key, per-repo signing key

**Host alias**:
A `Host github-<name>` entry in the SSH config that makes ssh use one deploy
key for one repository.
_Avoid_: remote name, SSH profile
