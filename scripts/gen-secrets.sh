#!/usr/bin/env bash
# gen-secrets.sh: tajne se GENERIŠU pri pokretanju (nasumično).
# Pravi: .vault_pass i šifrovani ansible/group_vars/all/vault.yml.
# Idempotentno: ako vault.yml već postoji, ne dira ga.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Vault lozinka ide VAN projekta, na ext4 home ($HOME) — da nije world-writable/izvršna
VP="${RUO_VAULT_PASS:-$HOME/.ruo_vault_pass}"
VAULT="$ROOT/ansible/group_vars/all/vault.yml"

command -v ansible-vault >/dev/null 2>&1 || { echo "Nedostaje ansible-vault. Pokreni ./scripts/00-setup.sh"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "Nedostaje openssl."; exit 1; }

if [ ! -f "$VP" ]; then
  openssl rand -base64 24 > "$VP"
  chmod 600 "$VP"
  echo "napravljen $VP (0600, van Gita)"
fi

if [ -f "$VAULT" ]; then
  echo "$VAULT već postoji — preskačem (obriši ga ručno za regeneraciju)."
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
{
  echo "---"
  echo "# Generisano skriptom gen-secrets.sh (nasumične vrijednosti)."
  echo "vault_db_password: \"$(openssl rand -base64 18 | tr -d '/+=' )\""
  echo "vault_jwt_secret: \"$(openssl rand -base64 48 | tr -d '\n')\""
  echo "vault_tsig_secret: \"$(openssl rand -base64 32)\""
} > "$TMP"

ansible-vault encrypt --vault-password-file "$VP" --output "$VAULT" "$TMP"
echo "napravljen šifrovani $VAULT"
echo "Napomena: vault lozinka je u $VP (van projekta), a vault.yml je šifrovan"
