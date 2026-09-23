#!/usr/bin/env bash
# Install or uninstall ssh-agent-shared by symlinking its files into $HOME.
#
# Usage:
#   ./install.sh               create the symlinks
#   ./install.sh --uninstall   remove them and restore the latest backups
#
# Installed links:
#   ~/.local/bin/<name>     -> <repo>/bin/<name>   (helper and auth scripts)
#   ~/.gitconfig-personal   -> <repo>/gitconfig-personal
#
# Rules:
#   - a symlink that already points to the right file is left alone;
#   - a regular file or a foreign symlink is renamed <name>.bak.<timestamp>;
#   - a directory in the way stops the install;
#   - rc files, ~/.gitconfig and ~/.ssh/config are never edited: the script
#     prints the lines to add by hand.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
BIN_DIR="$HOME/.local/bin"
HELPER=_ssh-agent-shared.sh
NOREPLY_EMAIL=1279695+fbenoit@users.noreply.github.com
STAMP=$(date +%Y%m%d-%H%M%S)

# Pairs of "source|destination".
links() {
  local src
  for src in "$REPO"/bin/*; do
    printf '%s|%s\n' "$src" "$BIN_DIR/$(basename "$src")"
  done
  printf '%s|%s\n' "$REPO/gitconfig-personal" "$HOME/.gitconfig-personal"
}

# owned <dest>: success when <dest> is a symlink created by this repo, or a
# dangling symlink left by a clone that has since moved.
owned() {
  local dest="$1" target
  [ -L "$dest" ] || return 1
  target=$(readlink "$dest")
  case "$target" in
    "$REPO"/*) return 0 ;;
  esac
  [ ! -e "$dest" ] && case "$target" in */ssh-agent-shared/*) return 0 ;; esac
  return 1
}

# replace <dest> <kind> <src>: atomically put a symlink (kind=link) or a copy
# (kind=copy) of <src> at <dest>.
replace() {
  local dest="$1" kind="$2" src="$3" tmp
  tmp="$dest.tmp.$$"
  if [ "$kind" = link ]; then
    ln -s "$src" "$tmp"
  else
    cp "$src" "$tmp"
  fi
  mv -Tf "$tmp" "$dest"
}

install_one() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "ok       $dest"
    return
  fi
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    echo "error: $dest is a directory; move it away and run again" >&2
    exit 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if owned "$dest"; then
      echo "relink   $dest"
    else
      mv "$dest" "$dest.bak.$STAMP"
      echo "backup   $dest -> $dest.bak.$STAMP"
    fi
  fi
  replace "$dest" link "$src"
  echo "link     $dest -> $src"
}

uninstall_one() {
  local src="$1" dest="$2" backup
  if ! owned "$dest"; then
    echo "skip     $dest (not installed by this repo)"
    return
  fi
  # Local scripts outside this repo may still source the helper: keep a copy.
  if [ "$(basename "$dest")" = "$HELPER" ] && [ -f "$src" ]; then
    replace "$dest" copy "$src"
    echo "copy     $dest (kept for scripts that source it)"
    return
  fi
  rm "$dest"
  echo "remove   $dest"
  backup=$(find "$(dirname "$dest")" -maxdepth 1 -name "$(basename "$dest").bak.*" 2>/dev/null | sort | tail -n 1)
  if [ -n "$backup" ]; then
    mv "$backup" "$dest"
    echo "restore  $dest from $backup"
    echo "warning: $dest is the version from before the install; it may use old key names" >&2
  fi
}

# hint <file> <pattern> <line>: print <line> unless <file> already matches.
hint() {
  local file="$1" pattern="$2" line="$3"
  if [ -f "$file" ] && grep -qF -- "$pattern" "$file"; then
    return
  fi
  printf '\nAdd to %s:\n%s\n' "$file" "$line"
}

do_install() {
  mkdir -p "$BIN_DIR"
  local pair
  while IFS= read -r pair; do
    install_one "${pair%%|*}" "${pair#*|}"
  done < <(links)

  # shellcheck disable=SC2016 # the line is printed, not expanded
  hint "$HOME/.$(basename "${SHELL:-bash}")rc" 'agent.sock' 'export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"'
  hint "$HOME/.gitconfig" 'gitconfig-personal' '[includeIf "gitdir:~/Personal/"]
	path = ~/.gitconfig-personal'
  hint "$HOME/.ssh/config" 'ssh-agent-shared/ssh_config.d' "Include $REPO/ssh_config.d/*.conf   (at the top of the file)"

  local email
  email=$(git -C "$REPO" config user.email || true)
  if [ "$email" != "$NOREPLY_EMAIL" ]; then
    printf '\nwarning: commits in %s would use "%s", not %s.\n' "$REPO" "$email" "$NOREPLY_EMAIL" >&2
    echo "Add the includeIf block above to ~/.gitconfig before committing." >&2
  fi
}

do_uninstall() {
  local pair
  while IFS= read -r pair; do
    uninstall_one "${pair%%|*}" "${pair#*|}"
  done < <(links)
  echo
  echo "Remove the lines you added by hand to ~/.zshrc, ~/.gitconfig and ~/.ssh/config."
}

case "${1:-}" in
  "") do_install ;;
  --uninstall) do_uninstall ;;
  *)
    echo "usage: $0 [--uninstall]" >&2
    exit 2
    ;;
esac
