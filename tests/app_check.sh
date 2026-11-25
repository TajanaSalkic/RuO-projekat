#!/usr/bin/env bash
# Provjera aplikacije: web vraća frontend, a login prolazi tok web -> app -> db.
set -uo pipefail
WEB="${WEB_URL:-http://10.40.1.10}"

echo "== AO-1 aplikacija (web -> app -> db) =="
rc=0

code=$(curl -s -o /dev/null -w '%{http_code}' "$WEB/")
if [ "$code" = "200" ]; then echo "  PASS  GET $WEB/ -> HTTP 200 (Angular)"; else echo "  FAIL  GET $WEB/ -> HTTP $code"; rc=1; fi

resp=$(curl -s -X POST "$WEB/api/users/login" -H 'Content-Type: application/json' \
  -d '{"email":"admin@ruo.lab","password":"Admin123!"}')
if echo "$resp" | grep -q '"token"'; then
  echo "  PASS  login admin@ruo.lab -> token (web->app->db radi)"
else
  echo "  FAIL  login -> ${resp:0:200}"; rc=1
fi

exit $rc
