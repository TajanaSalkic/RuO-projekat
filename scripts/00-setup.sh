#!/usr/bin/env bash
# 00-setup.sh — Faza 0: instalira i podešava alate za projekat "Troslojna aplikacija kao kod" (RuO 2026/27).
# Pokreće se U WSL2 Ubuntu 24.04 (ili Ubuntu/Debian Linuxu), kao OBIČAN korisnik (sudo se traži po potrebi).
#
#   ./scripts/00-setup.sh                  instalacija svega potrebnog za Opciju B (libvirt/KVM)
#   SKIP_LIBVIRT=1 ./scripts/00-setup.sh   bez KVM/libvirt (fallback na Docker provider; vidi docs/00-okruzenje.md)
#   INSTALL_DOCKER=0 ./scripts/00-setup.sh ne instaliraj Docker Engine (koristim Docker Desktop + WSL integraciju)
#
# Skripta je IDEMPOTENTNA: sigurno se pokreće više puta.
# Instalira samo ono što projekat treba (bez k8s/mail/garage iz predmetnog repoa, jer app i baza idu u kontejnere).
set -euo pipefail

SKIP_LIBVIRT="${SKIP_LIBVIRT:-0}"
INSTALL_DOCKER="${INSTALL_DOCKER:-1}"

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_step=$'\033[1;36m'; c_off=$'\033[0m'
step() { printf '\n%s== %s%s\n' "$c_step" "$*" "$c_off"; }
ok()   { printf '  %sok%s    %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!!%s    %s\n' "$c_warn" "$c_off" "$*"; }
err()  { printf '  %sXX%s    %s\n' "$c_err" "$c_off" "$*"; }

[ "$(id -u)" -ne 0 ] || { echo "Ne pokretati kao root; skripta sama koristi sudo."; exit 1; }
[ "$(uname -s)" = "Linux" ] || { echo "Potreban je Linux ili WSL2."; exit 1; }
command -v apt-get >/dev/null 2>&1 || { echo "Podržan je samo apt (Ubuntu/Debian)."; exit 1; }
sudo -v

IN_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && IN_WSL=1
HAS_SYSTEMD=0; [ "$(ps -p 1 -o comm= 2>/dev/null || true)" = "systemd" ] && HAS_SYSTEMD=1
NEED_RELOGIN=0

step "1/7 Provjera okruženja"
ok "$(. /etc/os-release && echo "$PRETTY_NAME")  kernel $(uname -r)"
if [ "$IN_WSL" = 1 ]; then
  ok "WSL2 detektovan"
  if [ "$HAS_SYSTEMD" = 0 ]; then
    warn "systemd NIJE uključen (potreban za libvirt/docker servise)."
    if ! grep -qs '^\s*systemd\s*=\s*true' /etc/wsl.conf; then
      printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
      warn "dodano 'systemd=true' u /etc/wsl.conf."
    fi
    warn "U PowerShellu (Windows) pokrenuti:  wsl --shutdown"
    warn "zatim ponovo otvoriti Ubuntu i ponovo pokrenuti ovu skriptu."
  fi
fi
if [ -e /dev/kvm ]; then
  ok "/dev/kvm postoji (hardverska virtualizacija dostupna)"
else
  err "/dev/kvm NE postoji — nested virtualizacija nije aktivna."
  warn "Uzrok je obično: (a) virtualizacija isključena u BIOS-u (SVM/VT-x), ili"
  warn "(b) nedostaje .wslconfig s 'nestedVirtualization=true'. Vidi docs/00-okruzenje.md."
  warn "Opcija B (libvirt/KVM) neće raditi dok se ovo ne riješi. Fallback: SKIP_LIBVIRT=1 (Docker provider)."
fi

step "2/7 Osnovni paketi (git, make, curl, ansible, mrežni alati)"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git make curl wget gnupg lsb-release ca-certificates software-properties-common \
  python3 python3-yaml python3-pip openssh-client ansible \
  iproute2 iputils-ping nftables bind9-dnsutils jq rsync
ok "git, make, curl, ansible, iproute2, nftables, dig (bind9-dnsutils), jq"

step "3/7 HashiCorp repozitorij: Terraform"
KEYRING=/usr/share/keyrings/hashicorp-archive-keyring.gpg
if [ ! -f "$KEYRING" ]; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o "$KEYRING"
fi
echo "deb [signed-by=$KEYRING] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y terraform
ok "terraform"

step "4/7 KVM i libvirt"
if [ "$SKIP_LIBVIRT" = 1 ]; then
  warn "preskočeno (SKIP_LIBVIRT=1) — koristi se Docker provider fallback."
else
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    qemu-system-x86 libvirt-daemon-system libvirt-clients virtinst genisoimage dnsmasq-base
  for g in libvirt kvm; do
    case " $(id -nG "$USER") " in
      *" $g "*) ;;
      *) sudo usermod -aG "$g" "$USER"; NEED_RELOGIN=1 ;;
    esac
  done
  if [ "$HAS_SYSTEMD" = 1 ]; then
    sudo systemctl enable --now libvirtd
    V="sudo virsh -c qemu:///system"
    if ! $V pool-info default >/dev/null 2>&1; then
      $V pool-define-as default dir --target /var/lib/libvirt/images
      $V pool-autostart default
    fi
    $V pool-start default >/dev/null 2>&1 || true
    if $V list --all >/dev/null 2>&1; then ok "libvirt radi (virsh dostupan), pool 'default' postoji"; else warn "virsh ne odgovara — provjeri systemd/KVM"; fi
  else
    warn "systemd nije aktivan: libvirt servis nije pokrenut"
  fi
fi

step "5/7 Docker Engine + Compose"
if command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
  ok "docker već radi: $(docker --version)"
elif [ "$INSTALL_DOCKER" = 1 ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2; then
    warn "docker-compose-v2 nedostupan na ovoj verziji; na Ubuntu 24.04 je dostupan. Alternativa: Docker Desktop."
  fi
  case " $(id -nG "$USER") " in *" docker "*) ;; *) sudo usermod -aG docker "$USER"; NEED_RELOGIN=1 ;; esac
  [ "$HAS_SYSTEMD" = 1 ] && sudo systemctl enable --now docker || true
  ok "Docker Engine instaliran"
else
  warn "Docker preskočen (INSTALL_DOCKER=0). U WSL2: Docker Desktop + WSL integracija."
fi

step "6/7 SSH ključ za virtualne mašine (cloud-init ga injektira)"
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  ok "~/.ssh/id_ed25519 već postoji"
else
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$USER@ruo"
  ok "napravljen ~/.ssh/id_ed25519 (bez lozinke)"
fi

step "7/7 Provjera alata"
rc=0
for t in git make terraform ansible docker virsh nft ip dig ssh ssh-keygen; do
  if command -v "$t" >/dev/null 2>&1 || [ -x "/usr/sbin/$t" ]; then ok "$t"; else warn "$t nije instaliran"; rc=1; fi
done
command -v terraform >/dev/null 2>&1 && terraform version | sed -n 1p || true
command -v ansible   >/dev/null 2>&1 && ansible --version | sed -n 1p || true

printf '\n%sGotovo.%s Sljedeće: ./scripts/check-env.sh  (ili  make check)\n' "$c_ok" "$c_off"
if [ "$NEED_RELOGIN" = 1 ]; then
  warn "Dodani ste u nove grupe (libvirt/kvm/docker). Zatvorite WSL (PowerShell: wsl --shutdown) i otvorite ponovo."
fi
exit $rc
