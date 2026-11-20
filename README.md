# workbench

Ansible playbooks and roles for my Macs and Linux servers: dotfiles,
LazyVim, tools and server configuration. The inventory and secrets are
encrypted with Ansible Vault; see `inventory.example.yml` for the
structure.

## Requirements

Control machine (where you run Ansible):

- macOS or Linux
- Python 3.12+
- Ansible (ansible-core 2.21+)
- gopass with the age backend (holds the vault password)

Managed machines:

- SSH access
- Python 3.9+

## Install

```sh
brew install python@3.12 pipx
pipx ensurepath
pipx install --include-deps --python python3.12 ansible
```

Check:

```sh
ansible --version
ansible-vault --version
```

Install the collections some playbooks depend on:

```sh
ansible-galaxy collection install -r requirements.yml
```

Some of those collections' modules need Python libraries that aren't
part of Ansible itself. Since Ansible runs in pipx's isolated venv,
install them with `pipx inject` rather than `pip install`:

```sh
pipx inject ansible requests
```

## Vault

Generate the vault password (once):

```sh
gopass generate workbench/ansible-vault 32
```

Cache the passphrase for 4h of idle time:

```sh
gopass config age.agent-timeout 14400
```

Encrypt / edit / view:

```sh
ansible-vault encrypt inventory.yml
ansible-vault edit inventory.yml
ansible-vault view inventory.yml
```

Edit without leaving plaintext in Neovim swap/undo/shada files:

```sh
# ~/.zshrc
vedit() {
  EDITOR="nvim -n -i NONE --cmd 'set noundofile nobackup nowritebackup'" \
    ansible-vault edit "$@"
}
```

Readable git diffs (per machine):

```sh
git config diff.ansible-vault.textconv "ansible-vault view"
```

## Git hook

`scripts/pre-commit.sh` encrypts staged files under the vault paths
(inventory, `group_vars/`, `host_vars/`, `playbooks/private/`) that are
still plaintext. Enable it once per clone:

```sh
ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
```

## Usage

```sh
cp inventory.example.yml inventory.yml   # first time, then fill in
ansible-playbook playbooks/<playbook>/main.yml -e target=macs
ansible-playbook playbooks/<playbook>/main.yml -e target=macs --tags lazyvim
ansible-playbook playbooks/<playbook>/main.yml -e target=macs --check --diff
```

## Layout

```txt
ansible.cfg
requirements.yml
inventory.yml            # encrypted
inventory.example.yml
playbooks/
  <playbook>/main.yml
  private/               # encrypted
roles/
  <role>/
    tasks/main.yml
    files/
scripts/
  pre-commit.sh
  vault-pass.sh
```
