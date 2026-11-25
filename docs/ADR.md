# Projektni zadatak - dizajnerske odluke (DO) i ADR-ovi

**Student:** Tajana Salkić<br>
**Git repozitorij:** https://github.com/TajanaSalkic/RuO-projekat<br>
**Predmet:** Računarstvo u oblaku · II ciklus, III semestar · akademska 2026/27<br>
**Univerzitet u Zenici, Politehnički fakultet**

---

## 1. Kratak opis aplikacije i arhitekture

Aplikacija je **MentorHub** - sistem za vođenje mentorstva i studentskih projekata: **Angular 19** frontend, **ASP.NET Core 8** backend i **PostgreSQL** baza, sa JWT autentifikacijom.

Infrastruktura implementira **pravi multi-VM VPC**: svaki sloj živi na svojoj virtuelnoj mašini u svom mrežnom segmentu (libvirt route mode), a izolaciju slojeva nameće `nftables` na hostu-ruteru. Imenovanje radi vlastiti autoritativni BIND9 DNS, a servisni DNS zapisi su Terraform resursi.

```
Internet ──HTTP/HTTPS -> ruo-web (10.40.1.10)  [Nginx + Angular]   - jedini ulaz izvana
                              │ /api -> app.ruo.lab:5000 (reverse proxy)
                              -> ruo-app (10.40.2.10)  [.NET 8 Web API :5000]
                              │ Host=db.ruo.lab :5432
                              -> ruo-db  (10.40.3.10)  [PostgreSQL 16 + named volume]  - izolovana
   ruo-dns (10.40.0.53) [BIND9 autoritativni, zona ruo.lab]
   WSL2 host = ruter + nftables (forward policy drop; web -> db blokiran)
```

Tok je `frontend -> backend -> baza`; frontend nema mrežni put do baze (dokazano testom izolacije).

---

## 2. Pregledna tabela dizajnerskih odluka

| ID | Pitanje | Izabrana opcija |
|---|---|---|
| DO-1 | Aplikacija i tehnologije po sloju? | MentorHub: Angular 19 / ASP.NET Core 8 / PostgreSQL 16 |
| DO-2 | Koliko VM-ova i raspored? | 4 VM (web/app/db/dns) na libvirt route-mode mrežama |
| DO-3 | Plan adresiranja? | 4 segmenta 10.40.0–3.0/24, statičke adrese preko cloud-init |
| DO-4 | Odakle bazna slika VM-a? | Zvanična Ubuntu 24.04 cloud slika + cloud-init |
| DO-5 | Kako se grade/distribuiraju kontejneri? | Multi-stage Dockerfile, build na ciljnoj VM |
| DO-6 | Kako Ansible dobija adrese VM-ova? | `local_file` inventory generisan iz Terraforma |
| DO-7 | Organizacija Ansible rola i varijabli? | Role po komponenti/funkciji; `group_vars` + `vault` |
| DO-8 | Projektovanje DNS zone? | Dinamička zona `ruo.lab`, TTL 300, TSIG, forwarding |
| DO-9 | Upravljanje tajnama? | `ansible-vault` + generisanje pri pokretanju |

---

## 3. Zapisi arhitektonskih odluka (ADR)

## DO-1: Aplikacija i tehnologije za svaki sloj
**Status:** prihvaćeno

### Kontekst
AO-1 traži troslojnu aplikaciju (frontend, backend, baza), svaku u svom kontejneru, s tokom `frontend -> backend -> baza`. AO-10 traži perzistentnu bazu. Treba izabrati aplikaciju i tehnologiju po sloju.

### Razmotrene opcije
1. Vlastita/open-source aplikacija s relacionom bazom (PostgreSQL).
2. Jednostavan laboratorijski primjer (Flask brojač posjeta, s3/p4).
3. Nerelaciona baza (MongoDB) ili datotečna (SQLite).

### Odluka
Koristi se vlastita aplikacija **MentorHub**: **Angular 19** (frontend), **ASP.NET Core 8** (backend), **PostgreSQL 16** (baza).

### Obrazloženje i posljedice
Angular i .NET Core su industrijski standard za troslojne poslovne sisteme sa jasnim razdvajanjem slojeva, što prirodno preslikava AO-1. PostgreSQL omogućava relacione mehanizme, uloge i EF migracije, te perzistentnost preko imenovanog volumena (AO-10). Flask primjer bi bio trivijalan i ne bi pokazao realan troslojni sistem; MongoDB nema relacione garancije, a SQLite je baza koja se ne bi mogla izolovati kao zaseban mrežni servis. Posljedica: build slojeva je zahtjevniji (NuGet/npm), što rješavamo multi-stage buildom (DO-5).

---

## DO-2: Broj VM-ova i raspored komponenti
**Status:** prihvaćeno

### Kontekst
AO-6 traži da su slojevi mrežno izolovani, svaki u svom segmentu, da je izvana dostupan samo frontend i da frontend nema pristup bazi. Način izvedbe (A: jedna VM s Docker mrežama; B: VM po segmentu).

### Razmotrene opcije
1. **Opcija A** - jedna VM, segmenti kao Docker mreže s fiksnim podmrežama.
2. **Opcija B** - po jedna VM za svaki sloj na libvirt mrežama u route modu, host usmjerava; DNS na zasebnoj VM.

### Odluka
**Opcija B** - četiri VM: `ruo-web`, `ruo-app`, `ruo-db` i namjenski `ruo-dns`.

### Obrazloženje i posljedice
Opcija B daje pravu infrastrukturnu izolaciju (odvojeni OS i kernel po sloju): kompromitacija frontenda ostavlja napadača izolovanog u web VM-u bez puta do diska baze. Terraform orkestrira set VM-ova (`for_each`), Ansible radi pravi multi-host inventar, a izolacija se nameće stvarnim rutiranjem i `nftables` firewall-om između segmenata. Opcija A bi dala softversku izolaciju (Docker mreže dijele isti Linux kernel i isti nftables namespace), dok Opcija B daje infrastrukturnu: kompromitacija Nginxa na web VM-u ostavlja napadača bez filesystem pristupa podacima baze. U javnom oblaku isti model odgovara VPC-u s odvojenim subnetsima po tieru i security groupama.

---

## DO-3: Plan adresiranja
**Status:** prihvaćeno

### Kontekst
AO-6 traži vlastitu podmrežu po segmentu. Adrese moraju biti determinisane da bi DNS i firewall bili predvidivi.

### Razmotrene opcije
1. Statičke adrese po segmentu (cloud-init network-config).
2. Dinamičke adrese (libvirt DHCP).

### Odluka
Četiri segmenta sa statičkim adresama:

| Segment | Podmreža | VM | IP | Gateway |
|---|---|---|---|---|
| mgmt/dns | 10.40.0.0/24 | ruo-dns | 10.40.0.53 | 10.40.0.1 |
| web | 10.40.1.0/24 | ruo-web | 10.40.1.10 | 10.40.1.1 |
| app | 10.40.2.0/24 | ruo-app | 10.40.2.10 | 10.40.2.1 |
| db | 10.40.3.0/24 | ruo-db | 10.40.3.10 | 10.40.3.1 |

### Obrazloženje i posljedice
Statičke adrese povezane s DNS imenima daju determinizam: `nftables` pravila i DNS zapisi su stabilni, a test izolacije je ponovljiv. DHCP bi unio nepredvidivost u kod. Adrese se postavljaju cloud-init network-config datotekom, bez DHCP-a. Posljedica: pri recreate-u VM-a adresa ostaje ista, pa inventory i DNS ne moraju da se mijenjaju. DHCP adrese bi značile da se pri svakom `make destroy && make all` adrese potencijalno mijenjaju - tri mjesta za sinhronizaciju (DNS zapisi, nftables pravila, Ansible inventory) umjesto jednog izvora istine (Terraform `var.vms` mapa).

---

## DO-4: Izvor bazne slike VM-a
**Status:** prihvaćeno

### Kontekst
AO-3/AO-4 traže da VM kreira Terraform, a početnu konfiguraciju cloud-init (korisnik sa SSH ključem, bez lozinke).

### Razmotrene opcije
1. Zvanična cloud slika (Ubuntu 24.04 `.img`) + cloud-init.
2. Vlastita slika izgrađena Packerom.

### Odluka
**Zvanična Ubuntu 24.04 (noble) cloud slika** + cloud-init.

### Obrazloženje i posljedice
Slika se preuzima jednom u libvirt pool, a svaka VM dobija brz copy-on-write qcow2 disk - čist princip nemutabilne infrastrukture. Cloud-init dinamički kreira korisnika `student`, injektira SSH ključ i gasi lozinke (AO-4). Packer bi zahtijevao statički pred-korak izgradnje slike (minute) koji se ponavlja pri svakoj promjeni paketa; cloud-init + cloud-image je fleksibilniji i standard u oblaku. Posljedica: prvi `make infra` troši ~1–2 min na preuzimanje slike (jednom). cloud-init je standard koji koristi npr. AWS (EC2 user-data), pa su koncepti (user-data, network-config) direktno prenosivi na javne oblake. Packer bi zahtijevao rebuild slike pri svakoj promjeni paketa ili verzije Ubuntu-a.

---

## DO-5: Izgradnja i distribucija kontejnerskih slika
**Status:** prihvaćeno

### Kontekst
AO-1 traži kontejnere po sloju. Slike treba graditi bez ovisnosti o eksternom registru tokom evaluacije.

### Razmotrene opcije
1. Multi-stage Dockerfile, build na ciljnoj VM.
2. Lokalni build + privatni/javni registry.
3. Javni registry (Docker Hub / GHCR).

### Odluka
**Multi-stage Dockerfile**, build na ciljnoj VM preko Ansible role.

### Obrazloženje i posljedice
Multi-stage build razdvaja build okruženje od runtime-a: Angular se gradi u `node:20-alpine` a izvršava u `nginx:alpine`; .NET se kompajlira u `sdk:8.0` a izvršava u `aspnet:8.0`. Produkcijske slike sadrže samo artefakte (bez SDK-a), što smanjuje površinu napada i veličinu. Build na ciljnoj VM čini sistem samodovoljnim - bez vlastitog registra i rizika rate-limitinga. Posljedica: prvi `make deploy` je sporiji (npm/NuGet restore na VM-u), ali idempotentan (ponovni build se ne izvodi ako slika postoji).

---

## DO-6: Kako Ansible dobija adrese VM-ova koje je kreirao Terraform
**Status:** prihvaćeno

### Kontekst
AO-2 traži da nema ručnih koraka između kreiranja VM-ova i konfiguracije.

### Razmotrene opcije
1. Ručno pisan inventory.
2. Inventory generisan iz Terraform outputa (`local_file`).
3. Dinamički libvirt inventory plugin.

### Odluka
Terraform **`local_file` resurs** generiše `ansible/inventory.ini` s grupama `[dns][web][app][db]`.

### Obrazloženje i posljedice
Inventory je resurs u istom `terraform apply` koraku koji kreira VM-ove, pa nema ručnog koraka (AO-2) i nema odstupanja između stvarnih adresa i inventara. Dinamički libvirt plugin bi zahtijevao dodatne C/Python biblioteke na hostu; `local_file` radi nativno u Terraformu. Inventory nije u Gitu (generiše se). Posljedica: promjena `var.vms` automatski regeneriše inventory. Dinamički libvirt inventory plugin (opcija 3) zahtijeva `libvirt-python` C biblioteku i autorisani `qemu:///system` socket na hostu - vanjska zavisnost koja nije deklarisana u kodu projekta i otežava ponovljivost. `local_file` je Terraform primitiv bez vanjskih zavisnosti koji garantuje konzistentnost unutar istog `apply` prolaza.

---

## DO-7: Organizacija Ansible rola i varijabli
**Status:** prihvaćeno

### Kontekst
AO-5 traži Ansible organizovan u role i idempotentan playbook.

### Razmotrene opcije
1. Modularne role po komponenti/funkciji + `group_vars`/`vault`.
2. Monolitni playbook bez rola.

### Odluka
**Role po funkciji:** `common`, `docker`, `firewall`, `dns`, `dns_client`, `app_db`, `app_backend`, `app_seed`, `app_web`. Globalne varijable u `group_vars/all/vars.yml`, tajne u šifrovanom `vault.yml`.

### Obrazloženje i posljedice
Separacija odgovornosti: svaka rola je nezavisna, idempotentna i lako testabilna; drugo izvršavanje daje `changed=0` (AO-5). Monolitni playbook bi otežao održavanje i idempotentnost. Redoslijed u `site.yml` je bitan (firewall/NAT -> čekanje na SSH -> common -> docker -> DNS -> aplikacija). Posljedica: `wait_for_connection` korak osigurava determinizam nakon `make infra` (cloud-init mreža). Svaka rola može biti primijenjena izolovano tagovima (`--tags docker`, `--tags dns`), što ubrzava razvoj i debugiranje. Razdvajanje tajni u `vault.yml` (šifrovano) od konfiguracije u `vars.yml` (čisto) znači da se `vars.yml` može dijeliti javno bez rizika, a `vault.yml` ostaje siguran čak i uz pristup repozitoriju.

---

## DO-8: Projektovanje DNS zone
**Status:** prihvaćeno

### Kontekst
AO-7 traži vlastitu autoritativnu BIND zonu i adresiranje isključivo imenima. AO-8 traži da su zapisi Terraform resursi (RFC 2136, TSIG ograničen na zonu projekta).

### Razmotrene opcije
1. Dinamička zona `ruo.lab` (TTL 300) + TSIG + rekurzija/forwarding za segmente.
2. Statička zonska datoteka (ručno uređivanje + serial bump).
3. Sekundarni/round-robin.

### Odluka
Autoritativna **dinamička zona `ruo.lab`** (TTL 300) na `ruo-dns`; TSIG ključ `ruo-tf` smije mijenjati samo tu zonu (`update-policy ... zonesub`); BIND forwarduje eksterne upite (`forwarders`, `allow-recursion` za 10.40.0.0/16). Servisni zapisi (web/app/db A, www CNAME) su Terraform resursi.

### Obrazloženje i posljedice
Dinamička zona omogućava da Terraform upravlja zapisima kao kodom (AO-8) i demonstraciju drifta (`nsupdate` -> `plan` -> `apply`). Svi servisi se adresiraju imenima (`http://app.ruo.lab:5000`, `Host=db.ruo.lab`), bez hardkodiranih IP adresa (AO-7). `~ruo.lab` routing na klijentima šalje samo `ruo.lab` upite BIND-u; kontejneri koriste `dns: 10.40.0.53`. Statička datoteka ne bi demonstrirala IaC upravljanje zapisima. Sekundarni server nije uveden; forwarders su DNS-infra IP-ovi, ne adresiranje servisa. Drift demonstracija pokazuje centralnu vrijednost "DNS kao kod": ručna izmjena zapisa (`nsupdate`) odmah se detektuje u `terraform plan` kao neslaganje između željenog i stvarnog stanja, i vraća se pri `apply`.

---

## DO-9: Upravljanje tajnama
**Status:** prihvaćeno

### Kontekst
AO-9 traži da tajne (lozinka baze, TSIG ključ, privatni ključevi) nikad nisu u Gitu u čistom obliku.

### Razmotrene opcije
1. `ansible-vault` + generisanje pri pokretanju.
2. `.env` van Gita.

### Odluka
**`ansible-vault`** šifruje `vault.yml` (lozinka baze, JWT tajna, TSIG tajna); vrijednosti se **generišu pri pokretanju** (`scripts/gen-secrets.sh`, `openssl rand`). Lozinka vaulta je u `~/.ruo_vault_pass` (0600, van projekta i Gita). U Gitu je samo `vault.yml.example`.

### Obrazloženje i posljedice
Čak i uz pregled cijele Git historije nema nijedne tajne u čistom tekstu (AO-9). Generisanje nasumičnih vrijednosti pri pokretanju eliminiše dijeljenje tajni. `make all` automatski poziva `make vault` prije podizanja, pa se na svježem klonu tajne generišu bez ijednog ručnog koraka (bitno za ponovljivost/AO-2). `.gitignore` blokira `.vault_pass`, `vault.yml`, `*.key`, `*.tfstate*`, `.env`. Posljedica: TSIG tajna iz vaulta se prosljeđuje Terraformu kao `sensitive` varijabla (`TF_VAR_tsig_secret`), pa i DNS upravljanje ostaje bez tajni u kodu. `.env` alternativa nije šifrovana na disku, nema auditnog traga promjena i zahtijeva ručno kreiranje. Generisanje nasumičnih vrijednosti pri prvom `make vault` eliminiše dijeljenje tajni između osoba.
