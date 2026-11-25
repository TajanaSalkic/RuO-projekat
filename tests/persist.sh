#!/usr/bin/env bash
# Podaci baze preživljavaju ponovno kreiranje kontejnera baze.
# SQL se prenosi base64-om da se izbjegne eskejpanje kroz ssh/docker/psql.
set -uo pipefail
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
DB=10.40.3.10

# VM-ovi su efemerni (novi host-ključ pri svakom rebuildu) -> ne pinujemo known_hosts, kao ansible.
R() { ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY" "student@$DB" "$@" 2>/dev/null; }
runsql() { # izvrši SQL na bazi preko base64, vrati -tA izlaz
  local b; b=$(printf '%s' "$1" | base64 -w0)
  R "echo $b | base64 -d | docker exec -i ruo-postgres psql -U mentorhub -d mentorhub -tA"
}

echo "== AO-10 perzistencija podataka =="
marker="PERSIST_$(date +%s)"

runsql "INSERT INTO \"Roles\"(\"Id\",\"Name\") VALUES (99,'$marker') ON CONFLICT (\"Id\") DO UPDATE SET \"Name\"=EXCLUDED.\"Name\";" >/dev/null
echo "  ubačen marker: $marker"

echo "  ponovno kreiram kontejner baze (compose down + up; named volume ostaje)..."
R "sudo docker compose -f /opt/ruo/compose.yaml down >/dev/null 2>&1; sudo docker compose -f /opt/ruo/compose.yaml up -d >/dev/null 2>&1"
R "for i in \$(seq 1 30); do docker exec ruo-postgres pg_isready -U mentorhub -d mentorhub >/dev/null 2>&1 && break; sleep 2; done"

got=$(runsql "SELECT \"Name\" FROM \"Roles\" WHERE \"Id\"=99;")
runsql "DELETE FROM \"Roles\" WHERE \"Id\"=99;" >/dev/null  # čišćenje

if [ "$got" = "$marker" ]; then
  echo "  PASS  podatak preživio recreate (pročitano: $got)"
  exit 0
else
  echo "  FAIL  marker izgubljen (pročitano: '$got')"
  exit 1
fi
