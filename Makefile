# Makefile — orkestracija projekta 
# Pokreće se u WSL2 Ubuntu.
# Tok odbrane:  make destroy  →  make all  →  make test  →  make all (idempotentno)

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.RECIPEPREFIX := >
.DEFAULT_GOAL := help

TF_VM  := terraform/vm
TF_DNS := terraform/dns
ANSIBLE_INV := ansible/inventory.ini
# -K traži sudo (become) lozinku hosta za localhost/firewall play; VM-ovi imaju NOPASSWD sudo.
ASK_BECOME ?= -K
# Projekat je na /mnt/c (world-writable) → Ansible ignoriše ansible.cfg osim ako ga eksplicitno damo.
export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg
# Vault lozinka je van projekta (ext4 home), da je /mnt/c 777 ne tretira kao izvršnu skriptu.
VAULT_PASS_FILE ?= $(HOME)/.ruo_vault_pass
VAULT_ARG := $(if $(wildcard $(VAULT_PASS_FILE)),--vault-password-file $(VAULT_PASS_FILE),)

c_step := \033[1;36m
c_off  := \033[0m
banner = printf '\n$(c_step)== %s$(c_off)\n' '$(1)'

##@ Pomoć
help: ## ovaj popis ciljeva
> @awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5)} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
> @printf '\nTok odbrane:  make destroy  →  make all  →  make test  →  make all\n'

##@ Pojedinačni koraci
check: ## provjera okruženja (alati, KVM, systemd)
> @$(call banner,check: provjera okruženja)
> ./scripts/check-env.sh

