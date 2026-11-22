#!/usr/bin/env bash
# check-env.sh — Faza 0: provjerava je li okruženje spremno i daje VERDIKT (Opcija B vs Docker fallback).
# Pokretati U WSL2 Ubuntu. Osnova za `make check`. Ne mijenja ništa; samo čita stanje.
set -uo pipefail

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_step=$'\033[1;36m'; c_off=$'\033[0m'
ok()   { printf '  %sOK%s   %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s??%s   %s\n' "$c_warn" "$c_off" "$*"; }
bad()  { printf '  %sXX%s   %s\n' "$c_err" "$c_off" "$*"; }
head() { printf '\n%s== %s%s\n' "$c_step" "$*" "$c_off"; }

fail=0; kvm_ok=1

head "Operativni sistem"
if [ "$(uname -s)" = "Linux" ]; then ok "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")  kernel $(uname -r)"
else bad "Nije Linux — pokreni ovo u WSL2 Ubuntu, ne u Git Bash/PowerShell."; exit 2; fi
grep -qi microsoft /proc/version 2>/dev/null && ok "WSL2 okruženje" || warn "nije WSL2 (ok ako si na native Linuxu)"

head "systemd (PID 1)"
if [ "$(ps -p 1 -o comm= 2>/dev/null || true)" = "systemd" ]; then ok "systemd je PID 1"
else bad "systemd NIJE PID 1 — dodaj [boot]\\nsystemd=true u /etc/wsl.conf, pa 'wsl --shutdown'"; fail=1; fi

head "Hardverska / nested virtualizacija"
if [ -e /dev/kvm ]; then
  ok "/dev/kvm postoji"
  [ -r /dev/kvm ] && [ -w /dev/kvm ] && ok "/dev/kvm čitljiv i upisiv za $USER" || warn "/dev/kvm bez r/w za $USER (dodaj se u grupu kvm, pa relogin)"
else
  bad "/dev/kvm NE postoji — Opcija B (libvirt/KVM) neće raditi"
  warn "Provjeri: (1) BIOS: virtualizacija (AMD SVM / Intel VT-x) UKLJUČENA"
  warn "          (2) %USERPROFILE%\\.wslconfig sadrži [wsl2] nestedVirtualization=true, pa 'wsl --shutdown'"
  kvm_ok=0; fail=1
fi

head "Alati (CLI)"
for t in git make terraform ansible docker virsh nft ip dig ssh ssh-keygen; do
  if command -v "$t" >/dev/null 2>&1 || [ -x "/usr/sbin/$t" ]; then ok "$t"; else bad "$t nedostaje — pokreni ./scripts/00-setup.sh"; fail=1; fi
done

head "libvirt / KVM servis"
if command -v virsh >/dev/null 2>&1; then
  if virsh -c qemu:///system list --all >/dev/null 2>&1; then
    ok "virsh -c qemu:///system radi"
    virsh -c qemu:///system pool-info default >/dev/null 2>&1 && ok "libvirt pool 'default' postoji" || warn "nema pool 'default' (00-setup.sh ga pravi)"
  else
    bad "virsh ne može do qemu:///system (libvirtd ne radi ili nema dozvola)"; [ "$kvm_ok" = 1 ] && fail=1
  fi
else bad "virsh nije instaliran"; fi

head "Docker"
if command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then ok "docker radi: $(docker --version)"
else warn "docker ne odgovara (Docker Desktop+WSL integracija ili INSTALL_DOCKER=1 ./scripts/00-setup.sh)"; fi

head "SSH ključ (za cloud-init)"
[ -f "$HOME/.ssh/id_ed25519.pub" ] && ok "~/.ssh/id_ed25519.pub postoji" || { bad "nema ~/.ssh/id_ed25519 — 00-setup.sh ga pravi"; fail=1; }

