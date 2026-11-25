#!/usr/bin/env bash
# Provjera: sva servisna imena se razrješavaju preko projektnog BIND-a.
set -euo pipefail
SERVER="${1:-10.40.0.53}"
echo "dig @$SERVER (zona ruo.lab)"
for n in web app db www ns; do
  printf "  %-12s -> " "$n.ruo.lab"
  dig +short "@$SERVER" "$n.ruo.lab" | paste -sd' ' -
done
echo "CNAME provjera:"
printf "  %-12s -> " "www.ruo.lab"
dig +short "@$SERVER" www.ruo.lab CNAME
