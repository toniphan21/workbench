#!/bin/sh
# Prints the Ansible Vault password; referenced by ansible.cfg.
exec gopass show -o workbench/ansible-vault
