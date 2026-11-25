# Priprema okruženja (WSL2 + KVM/libvirt)

Cijeli projekat se gradi i pokreće u **Linuxu (WSL2 Ubuntu 24.04)**. Za 4 virtuelne mašine preko libvirt/KVM potrebna je **nested virtualizacija** u WSL2, a za nju **hardverska virtualizacija uključena u BIOS-u**.

---

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

Provjeri je li nested virtualizacija već aktivna — ako jeste, preskoči ovaj korak:

```bash
# u WSL2 Ubuntu terminalu
grep -c vmx /proc/cpuinfo    # Intel: mora biti > 0
# ili
grep -c svm /proc/cpuinfo    # AMD: mora biti > 0
ls /dev/kvm && echo "KVM dostupan" || echo "KVM NIJE dostupan"
```

Ako `/dev/kvm` postoji i grep vraća broj > 0 — **preskoči na korak 4**, sve radi.
Ako ne postoji, nastavi ispod.

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
Pa u PowerShellu `wsl --shutdown` i ponovo otvorite Ubuntu. Provjera: `ps -p 1 -o comm=` -> treba ispisati `systemd`.
*(Skripta `00-setup.sh` ovo postavi automatski ako nije; svejedno traži `wsl --shutdown`.)*

## 5. Klonirati/otvoriti projekat u WSL2 i instalirati alate

Provjeri jesi li već u potrebnim grupama (preskači `wsl --shutdown` ako je sve OK):

```bash
groups $USER | grep -E 'libvirt|kvm|docker' && echo "Grupe OK" || echo "Trebaju se dodati (00-setup.sh + wsl --shutdown)"
```

Ako sve tri grupe postoje - nastavi direktno na korak 6 bez `wsl --shutdown`.
Ako neke nedostaju, pokreni `00-setup.sh` i nakon njega `wsl --shutdown`.

U WSL2 Ubuntu, iz korijena projekta:
```bash
chmod +x scripts/*.sh
./scripts/00-setup.sh
```
Instalira: `terraform`, `ansible`, `qemu/libvirt`, `docker`, `nftables`, `dig`, SSH ključ, i podesi libvirt (`pool default`). Idempotentna je.

- Bez KVM-a (fallback): `SKIP_LIBVIRT=1 ./scripts/00-setup.sh`
- Nakon što vas doda u grupe `libvirt/kvm/docker`: `wsl --shutdown` pa ponovo.


