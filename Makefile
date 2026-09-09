SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help setup doctor check update install-opencode update-opencode \
	auth-opencode status start stop restart logs tailscale-plan \
	bwrap-status bwrap-install bwrap-remove bwrap-test \
	codex-status codex-start codex-stop codex-pair

help: ## Show available commands
	@./bin/sparkctl help

setup: ## Install user configuration and systemd links
	@./bin/sparkctl setup

doctor: ## Diagnose host and service prerequisites
	@./bin/sparkctl doctor

check: ## Validate repository scripts and units
	@./scripts/check.sh

update: ## Fast-forward this checkout and refresh installed links
	@./bin/sparkctl update

install-opencode: ## Install the repository-pinned OpenCode version
	@./bin/sparkctl tool install opencode

update-opencode: ## Reinstall the repository-pinned OpenCode version
	@./bin/sparkctl tool update opencode

auth-opencode: ## Run OpenCode's interactive provider login
	@./bin/sparkctl auth opencode

status: ## Show OpenCode Web status
	@./bin/sparkctl service status

start: ## Start OpenCode Web
	@./bin/sparkctl service start opencode

stop: ## Stop OpenCode Web
	@./bin/sparkctl service stop opencode

restart: ## Restart OpenCode Web
	@./bin/sparkctl service restart opencode

logs: ## Follow OpenCode Web logs
	@./bin/sparkctl service logs opencode

tailscale-plan: ## Show a non-destructive OpenCode Serve command
	@./bin/sparkctl tailscale plan

codex-status: ## Show the Codex remote-control daemon and unit status
	@./bin/sparkctl codex status

codex-start: ## Start the Codex remote-control service
	@./bin/sparkctl codex start

codex-stop: ## Stop the Codex remote-control service
	@./bin/sparkctl codex stop

codex-pair: ## Run Codex's interactive remote-control pairing
	@./bin/sparkctl codex pair

bwrap-status: ## Diagnose bubblewrap/AppArmor
	@./scripts/bwrap-apparmor.sh status

bwrap-install: ## Install Ubuntu's stacked bubblewrap AppArmor profile
	@./scripts/bwrap-apparmor.sh install

bwrap-remove: ## Disable and archive the managed AppArmor profile
	@./scripts/bwrap-apparmor.sh remove

bwrap-test: ## Test bubblewrap user and network namespaces
	@./scripts/bwrap-apparmor.sh test

