#!/usr/bin/env bash
# Encrypts staged files that must be vaulted but are still plaintext.
set -eu

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Pathspecs of files that must be committed encrypted.
VAULT_PATHS=(
  inventory.yml
  group_vars/
  host_vars/
  playbooks/private/
  ':(exclude,glob)**/.gitkeep'
)

status=0

while IFS= read -r -d '' f; do
  # Check the staged content, not the working tree.
  if git cat-file blob ":$f" | head -n 1 | grep -q '^\$ANSIBLE_VAULT;'; then
    continue
  fi

  # Encrypting rewrites the whole file; refuse if the working tree has
  # unstaged changes, or they would be silently committed too.
  if ! git diff --quiet -- "$f"; then
    echo "pre-commit: $f is plaintext and has unstaged changes; stage or stash them first" >&2
    status=1
    continue
  fi

  ansible-vault encrypt "$f"
  git add -- "$f"
  echo "pre-commit: encrypted $f"
done < <(git diff --cached --name-only -z --diff-filter=ACMR -- "${VAULT_PATHS[@]}")

exit "$status"
