# Troslojna aplikacija kao kod — MentorHub

Projektni zadatak iz predmeta **Računarstvo u oblaku**. Kompletna infrastruktura za troslojnu web aplikaciju opisana **isključivo kodom**: virtuelne mašine (Terraform), konfiguracija (Ansible), kontejneri (Docker), segmentirana mreža (nftables) i autoritativni DNS (BIND9 + Terraform DNS zapisi).

> **Aplikacija:** MentorHub — **Angular 19** (frontend) · **ASP.NET Core 8** (backend) · **PostgreSQL 16** (baza).
> **Dizajnerske odluke i ADR-ovi:** [`docs/ADR.md`](docs/ADR.md) · **Priprema okruženja:** [`docs/00-okruzenje.md`](docs/00-okruzenje.md)

## Arhitektura

```
Internet ─ HTTP/HTTPS -> ruo-web (10.40.1.10)  [Nginx + Angular]   — jedini ulaz izvana
                              │ /api → app.ruo.lab:5000 (reverse proxy)
                              -> ruo-app (10.40.2.10)  [.NET 8 Web API :5000]
                                  Host=db.ruo.lab :5432
                              │   
                              -> ruo-db  (10.40.3.10)  [PostgreSQL 16 + named volume]  — izolovana
                ruo-dns (10.40.0.53) [BIND9 autoritativni, zona ruo.lab]
                WSL2 host = ruter + nftables (forward policy drop; web↛db blokiran)
```

Tok je `frontend -> backend -> baza`.

### Plan adresiranja i izolacija

| Segment | Podmreža | VM | IP |
|---|---|---|---|
| mgmt/dns | 10.40.0.0/24 | ruo-dns | 10.40.0.53 |
| web | 10.40.1.0/24 | ruo-web | 10.40.1.10 |
| app | 10.40.2.0/24 | ruo-app | 10.40.2.10 |
| db | 10.40.3.0/24 | ruo-db | 10.40.3.10 |

Svaki sloj je u svojoj libvirt route-mode mreži. `nftables` na hostu (forward `policy drop`) dozvoljava samo: `internet->web:80,443`, `web->app:5000`, `app->db:5432`, i izlaz na internet za segmente; **`web->db` nema puta**. Baza nema pristup izvan db segmenta.

## Struktura repozitorija

```
app/
  frontend/     Angular 19 + Dockerfile (node:20 -> nginx:alpine) + nginx.conf
  backend/      ASP.NET Core 8 + Dockerfile (sdk:8.0 -> aspnet:8.0)
terraform/vm/   VM-ovi i segmentirane mreže + generisani inventory
terraform/dns/  DNS zapisi servisa (hashicorp/dns, RFC 2136)
cloud-init/     user-data + network-config
ansible/        role: common, docker, firewall, dns, dns_client, app_*
tests/          test_isolation, dig, app_check, persist, drift_demo
scripts/        00-setup.sh, check-env.sh, gen-secrets.sh, tsig-secret.sh
docs/           ADR.md (DO + ADR za PDF), 00-okruzenje.md
Makefile        check / infra / config / dns / deploy / test / all / destroy
```

## Pokretanje od praznog računara

### Šta mora postojati na Windowsu

| Šta | Kako |
|---|---|
| **WSL2 s Ubuntu 22.04 ili 24.04** | PowerShell: `wsl --install -d Ubuntu` |
| **Docker Desktop** s uključenom WSL integracijom | Docker Desktop -> Settings -> Resources -> WSL integration -> uključiti Ubuntu |

Linux korisnici nemaju ovaj korak: dovoljno je Ubuntu/Debian s `apt`.

**Preduslov:** WSL2 Ubuntu 24.04 s uključenom virtualizacijom (BIOS) i nested virtualizacijom. Detaljno u [`docs/00-okruzenje.md`](docs/00-okruzenje.md).
Unutar [`docs/00-okruzenje.md`](docs/00-okruzenje.md) možete pronaći sljedeće korake koje potrebno izvršiti prije kloniranja repozitorija: 

## 1. BIOS: uključiti virtualizaciju (obavezno prvo)

1. Restartujte računar i uđite u BIOS/UEFI.
2. Pronađite i **uključite** (Enabled):
   - AMD CPU: **SVM Mode** (Secure Virtual Machine).
   - Intel CPU: **Intel Virtualization Technology (VT‑x)** i, ako postoji, **VT‑d**.
   - Opcija je često pod *Advanced → CPU Configuration*.
3. Snimite (`F10`) i izađite.
4. Provjera u Windowsu nakon boot‑a — u PowerShellu:
   ```powershell
   systeminfo | Select-String "Virtualization"
   ```
   Treba pisati `Virtualization Enabled In Firmware: Yes` (ili Task Manager -> Performance -> CPU -> *Virtualization: Enabled*).

## 2. Uključiti Windows funkcije i instalirati WSL2

U **PowerShellu kao Administrator**:
```powershell
wsl --install -d Ubuntu-24.04
```
Ovo uključuje "Virtual Machine Platform" i "WSL", instalira Ubuntu 24.04 i kernel. **Restartujte** ako to zatraži. Pri prvom pokretanju Ubuntua napravite Linux korisnika (ovo nije root; skripte koriste `sudo`).

Provjera verzije (treba `VERSION 2`):
```powershell
wsl -l -v
```

## 3. Omogućiti nested virtualizaciju (`.wslconfig`)

Na Windowsu kreirajte/uredite `%USERPROFILE%\.wslconfig` (tj. `C:\Users\<vi>\.wslconfig`) — primjer je u [`wslconfig.primjer`](wslconfig.primjer):
```ini
[wsl2]
nestedVirtualization=true
memory=6GB      # 4 VM po 1GB + overhead; podesite prema RAM-u
processors=4
```
Zatim u PowerShellu:
```powershell
wsl --shutdown
```
i ponovo otvorite Ubuntu.

## 4. Uključiti systemd u WSL2

U Ubuntu terminalu (unutar WSL2):
```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```
Pa u PowerShellu `wsl --shutdown` i ponovo otvorite Ubuntu. Provjera: `ps -p 1 -o comm=` → treba ispisati `systemd`.
*(Skripta `00-setup.sh` ovo postavi automatski ako nije; svejedno traži `wsl --shutdown`.)*

Nako izvršenih koraka iz [`docs/00-okruzenje.md`](docs/00-okruzenje.md), sljedeće što je potrebno uraditi jeste:

```bash
# 0. Kloniraj repozitorij (u WSL2 Ubuntu)
git clone https://github.com/TajanaSalkic/RuO-projekat.git
cd RuO-projekat

# 1. Alati (jednom) — u WSL2 Ubuntu
./scripts/00-setup.sh
./scripts/check-env.sh        # verdikt

# 2. Tajne (jednom) — generiše ~/.ruo_vault_pass + šifrovani vault.yml
make vault

# 3. Podizanje, test, drugo izvršavanje (idempotentnost), uklanjanje
make all          # infra -> config (traži sudo lozinku jednom) -> dns -> deploy
make test         # izolacija, dig, aplikacija, perzistencija
make all          # drugo izvršavanje: changed=0
make destroy      # uklanja sve
```

> **Napomena o `make config`:** `firewall` play se primjenjuje na host (WSL2) i traži sudo lozinku jednom; VM-ovi imaju NOPASSWD sudo. `deploy`/`dns`/`test` ne traže lozinku.

**Pristup aplikaciji:** `http://10.40.1.10/` (ili `http://web.ruo.lab/` s mašine koja koristi projektni DNS).
Demo nalozi: `admin@ruo.lab` / `Admin123!`, `mentor1@ruo.lab` / `Mentor123!`, `student1@ruo.lab` / `Student123!`.

## Dokazi (stvarni ispisi)

> Ispisi su dobijeni tokom inicijalnog deploymentu. Pokretanjem `make all && make test` dobijate identičan izlaz na svježe podignutom okruženju.

### Terraform idempotentan (`terraform plan` nakon `apply`)
```
No changes. Your infrastructure matches the configuration.
```

### Idempotentnost — drugo izvršavanje `make all`
```
PLAY RECAP
localhost : ok=10  changed=0   unreachable=0  failed=0
ruo-app   : ok=13  changed=0   unreachable=0  failed=0
ruo-db    : ok=13  changed=0   unreachable=0  failed=0
ruo-dns   : ok=17  changed=0   unreachable=0  failed=0
ruo-web   : ok=13  changed=0   unreachable=0  failed=0
# terraform/vm i terraform/dns: "No changes"
```

### Demonstracija drifta (`make drift`)
```
[1] app.ruo.lab = 10.40.2.10                 (željeno stanje)
[2] nsupdate -> app.ruo.lab = 10.40.2.222      (drift van Terraforma)
[3] terraform plan -> "0 to add, 1 to change"  (drift DETEKTOVAN)
[4] terraform apply -> app.ruo.lab = 10.40.2.10 (VRAĆENO)
```

### `make test`
```
== AO-6 izolacija slojeva ==
  PASS  web -> db:5432  blokiran (TIMEOUT)
  PASS  app -> db:5432  dostupan (OPEN)
  PASS  web -> app:5000  dostupan (OPEN)
dig @10.40.0.53 (zona ruo.lab)
  web.ruo.lab -> 10.40.1.10 ; app.ruo.lab -> 10.40.2.10 ; db.ruo.lab -> 10.40.3.10
  www.ruo.lab -> web.ruo.lab. (CNAME)
== AO-1 aplikacija (web -> app -> db) ==
  PASS  GET http://10.40.1.10/ -> HTTP 200 (Angular)
  PASS  login admin@ruo.lab -> token (web->app->db radi)
== AO-10 perzistencija podataka ==
  PASS  podatak preživio recreate kontejnera baze
SVI TESTOVI PROŠLI
```

## Česti problemi

| Simptom | Provjera |
|---------|----------|
| `make infra` staje na SSH | cloud-init još nije završio — retry je automatski (`wait_for_connection`) |
| `make test` — web->db nije TIMEOUT | Provjeri `make config` i je li `nftables` učitan: `sudo nft list ruleset` |
| DNS ne razrješava ruo.lab | `dig @10.40.0.53 web.ruo.lab` ručno; provjeri je li `make dns` pokrenuto |
| `virsh: Permission denied` | `newgrp libvirt` ili `wsl --shutdown` pa ponovo otvori |
| `make vault` greška | Provjeri je li `ansible-vault` instaliran: `./scripts/check-env.sh` |

## Tajne i Git

U Git ne idu: `*.tfstate`, `.terraform/`, `.env`, privatni SSH/TSIG ključevi, nešifrovane lozinke, generisani `inventory.ini`. Vidi [`.gitignore`](.gitignore). Stvarni `vault.yml` je šifrovan (ansible-vault), lozinka vaulta je u `~/.ruo_vault_pass` (van projekta). U Gitu je samo `vault.yml.example`.

## Preslikavanje obaveznih odluka

| AO | Gdje | Provjera |
|---|---|---|
| AO-1 troslojna app u kontejnerima | `app/`, `ansible/roles/app_*` | `make test` (login) |
| AO-2 sve kao kod, bez ručnih koraka | `Makefile` | `make destroy && make all` |
| AO-3 VM kreira Terraform | `terraform/vm/` | `terraform plan` = 0 |
| AO-4 cloud-init, SSH, bez lozinke | `cloud-init/` | pregled user-data, SSH |
| AO-5 Ansible role, idempotentno | `ansible/roles/` | 2. run `changed=0` |
| AO-6 mrežna izolacija | `ansible/roles/firewall` | `tests/test_isolation.sh` |
| AO-7 autoritativni BIND, imena | `ansible/roles/dns` | `tests/dig.sh` |
| AO-8 DNS zapisi kao Terraform | `terraform/dns/` | `tests/drift_demo.sh` |
| AO-9 tajne van Gita | `ansible-vault`, `.gitignore` | pregled historije |
| AO-10 perzistencija baze | `app_db` named volume | `tests/persist.sh` |
