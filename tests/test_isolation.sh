#!/usr/bin/env bash
# Test izolacije: frontend (web) NE smije imati mrežni put do baze (db).
# app->db i web->app smiju. Vraća exit 1 ako je izolacija narušena.
set -uo pipefail
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

probe() { # $1 ssh-host  $2 dst-ip  $3 port  -> OPEN|REFUSED|TIMEOUT|ERR
  # VM-ovi su efemerni (novi host-ključ pri svakom rebuildu) -> ne pinujemo known_hosts.
  ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -i "$KEY" "student@$1" "python3 - $2 $3" 2>/dev/null <<'PY'
import socket, sys
s = socket.socket(); s.settimeout(3)
try:
    s.connect((sys.argv[1], int(sys.argv[2]))); print("OPEN")
except ConnectionRefusedError: print("REFUSED")
except (TimeoutError, socket.timeout): print("TIMEOUT")
except Exception as e: print("ERR:" + type(e).__name__)
PY
}

echo "== AO-6 izolacija slojeva =="
rc=0

r=$(probe 10.40.1.10 10.40.3.10 5432)
if [ "$r" = "TIMEOUT" ]; then echo "  PASS  web -> db:5432  blokiran ($r)"; else echo "  FAIL  web -> db:5432 = $r (mora biti TIMEOUT)"; rc=1; fi

r=$(probe 10.40.2.10 10.40.3.10 5432)
if [ "$r" = "OPEN" ] || [ "$r" = "REFUSED" ]; then echo "  PASS  app -> db:5432  dostupan ($r)"; else echo "  FAIL  app -> db:5432 = $r (mora biti dostupan)"; rc=1; fi

r=$(probe 10.40.1.10 10.40.2.10 5000)
if [ "$r" = "OPEN" ] || [ "$r" = "REFUSED" ]; then echo "  PASS  web -> app:5000  dostupan ($r)"; else echo "  FAIL  web -> app:5000 = $r (mora biti dostupan)"; rc=1; fi

exit $rc
