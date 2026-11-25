#!/usr/bin/env bash
# Demonstracija drifta: promijeni DNS zapis VAN Terraforma (nsupdate preko TSIG-a),
# pokaži da ga `terraform plan` detektuje, pa `terraform apply` vraća u željeno stanje.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRET="$("$ROOT/scripts/tsig-secret.sh")"
SERVER="${SERVER:-10.40.0.53}"
export TF_VAR_tsig_secret="$SECRET"

echo "== [1] Trenutno stanje app.ruo.lab =="
dig +short "@$SERVER" app.ruo.lab

echo "== [2] DRIFT: mijenjam app.ruo.lab -> 10.40.2.222 preko nsupdate (van Terraforma) =="
nsupdate -y "hmac-sha256:ruo-tf.:$SECRET" <<EOF
server $SERVER
zone ruo.lab.
update delete app.ruo.lab. A
update add app.ruo.lab. 300 A 10.40.2.222
send
EOF
sleep 1
echo "   sada: $(dig +short "@$SERVER" app.ruo.lab)"

echo "== [3] terraform plan (treba da prijavi promjenu na app) =="
cd "$ROOT/terraform/dns"
terraform plan -no-color -input=false | grep -E "must be replaced|will be updated|# dns_a_record_set|~|Plan:" | head -n 15 || true

echo "== [4] terraform apply (vraća app.ruo.lab na 10.40.2.10) =="
terraform apply -auto-approve -no-color -input=false | tail -n 3
sleep 1
echo "   nakon apply: $(dig +short "@$SERVER" app.ruo.lab)"
