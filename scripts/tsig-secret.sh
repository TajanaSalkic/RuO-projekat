#!/usr/bin/env bash
# Ispisuje dešifrovanu TSIG tajnu (vault_tsig_secret) iz ansible-vault-a.
# Koristi ga Makefile da je proslijedi Terraformu kao TF_VAR_tsig_secret.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VP="${RUO_VAULT_PASS:-$HOME/.ruo_vault_pass}"
VAULT="$ROOT/ansible/group_vars/all/vault.yml"

[ -f "$VP" ] || { echo "Nema vault lozinke ($VP). Pokreni: make vault" >&2; exit 1; }
[ -f "$VAULT" ] || { echo "Nema $VAULT. Pokreni: make vault" >&2; exit 1; }

ansible-vault view --vault-password-file "$VP" "$VAULT" \
  | sed -n 's/^vault_tsig_secret:[[:space:]]*//p' \
  | sed 's/^"//; s/"$//'
