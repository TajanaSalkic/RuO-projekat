# Makefile — orkestracija projekta 
# Pokreće se u WSL2 Ubuntu.
# Tok odbrane:  make destroy  -> make all  ->  make test  ->  make all (idempotentno)

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.RECIPEPREFIX := >
.DEFAULT_GOAL := help

TF_VM  := terraform/vm
TF_DNS := terraform/dns
ANSIBLE_INV := ansible/inventory.ini
# -K traži sudo (become) lozinku hosta za localhost/firewall play; VM-ovi imaju NOPASSWD sudo.
ASK_BECOME ?= -K
export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg
VAULT_PASS_FILE ?= $(HOME)/.ruo_vault_pass
VAULT_ARG := $(if $(wildcard $(VAULT_PASS_FILE)),--vault-password-file $(VAULT_PASS_FILE),)

c_step := \033[1;36m
c_off  := \033[0m
banner = printf '\n$(c_step)== %s$(c_off)\n' '$(1)'
todo   = { printf '\n$(c_step)== %s$(c_off)\n' '$(1)'; echo "   [još nije implementirano — $(2)]"; }

.PHONY: help check infra infra-plan config vault dns drift deploy test all destroy

##@ Pomoć
help: ## ovaj popis ciljeva
> @awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5)} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
> @printf '\nTok odbrane:  make destroy  ->  make all  ->  make test  ->  make all\n'

##@ Pojedinačni koraci
check: ## provjera okruženja (alati, KVM, systemd)
> @$(call banner,check: provjera okruženja)
> ./scripts/check-env.sh


infra: ## Terraform: kreiranje VM-ova i segmentiranih mreža
> @$(call banner,infra: terraform/vm (init + apply))
> cd $(TF_VM) && terraform init -input=false && terraform apply -auto-approve
> @echo "   inventory → $(ANSIBLE_INV)"

infra-plan: ## samo prikaži šta bi infra uradila (terraform plan)
> cd $(TF_VM) && terraform init -input=false && terraform plan

config: ## Ansible: NAT+izolacija, osnovna konfiguracija, Docker, DNS server
> @$(call banner,config: ansible (firewall + common + docker + DNS server))
> cd ansible && ansible-playbook site.yml --tags firewall,base,docker,dns $(ASK_BECOME) $(VAULT_ARG)

vault: ## generiše .vault_pass + šifrovani vault.yml sa nasumičnim tajnama
> @$(call banner,vault: generisanje tajni)
> ./scripts/gen-secrets.sh

dns: ## Terraform: DNS zapisi servisa kao kod
> @$(call banner,dns: terraform/dns apply (TSIG iz vaulta))
> cd $(TF_DNS) && terraform init -input=false && TF_VAR_tsig_secret="$$($(CURDIR)/scripts/tsig-secret.sh)" terraform apply -auto-approve

drift: ## Demonstracija drifta (nsupdate -> plan detektuje -> apply ispravi)
> ./tests/drift_demo.sh

deploy: ## Ansible: build i pokretanje MentorHub kontejnera + baza/seed
> @$(call banner,deploy: isporuka aplikacije (db + backend + seed + web))
> cd ansible && ansible-playbook site.yml --tags app --limit 'db:app:web' $(VAULT_ARG)

test: ## testovi: izolacija (web↛db), dig upiti, app, perzistencija
> @$(call banner,test: verifikacija (izolacija, dig, app, perzistencija))
> @rc=0; for t in tests/test_isolation.sh tests/dig.sh tests/app_check.sh tests/persist.sh; do \
>   printf '\n--- %s ---\n' "$$t"; bash "$$t" || rc=1; done; \
>   if [ $$rc -eq 0 ]; then echo; echo "SVI TESTOVI PROŠLI"; else echo; echo "NEKI TEST PAO"; fi; exit $$rc

##@ Sve / uklanjanje
all: vault infra config dns deploy ## svi koraci redom (od praznog sistema do aplikacije)
> @$(call banner,all: gotovo)

destroy: ## uklanja sve što je projekat kreirao (DNS zapisi, pa VM-ovi)
> @$(call banner,destroy: uklanjanje infrastrukture)
> @if [ -d $(TF_DNS)/.terraform ]; then cd $(TF_DNS) && TF_VAR_tsig_secret="$$($(CURDIR)/scripts/tsig-secret.sh 2>/dev/null || echo x)" terraform destroy -auto-approve || true; fi
> @if [ -d $(TF_VM)/.terraform ];  then cd $(TF_VM)  && terraform destroy -auto-approve || true; fi
