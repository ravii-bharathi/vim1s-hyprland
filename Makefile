# vim1s-desktop — laptop-side entry points. `make` lists targets.
#
# One-time laptop setup (Ubuntu 26.04, GNOME on Wayland):
#   sudo apt install podman distrobox     (both in universe)
#   make box                              build the pinned Arch image + create the distrobox
#
# The repo must live under $HOME: distrobox shares $HOME with the container.

BOARD  ?= alarm@vim1s.local
IMAGE  ?= vim1s-dev
BOX    ?= vim1s-dev
IN_BOX := distrobox enter $(BOX) --
BUNDLE ?= ../vim1s-desktop.bundle
# Package source for the test image: a YYYY/MM/DD Arch Linux Archive snapshot (reproducible),
# or empty for live mirrors (fast):  make image ARCHIVE_DATE=
ARCHIVE_DATE ?= 2026/10/08

.DEFAULT_GOAL := help
.PHONY: help image box validate validate-offline nested-hypr nested-sway bundle deploy install-board check-board

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-17s %s\n", $$1, $$2}'
	@echo "  variables: BOARD=$(BOARD) IMAGE=$(IMAGE) BOX=$(BOX) ARCHIVE_DATE=$(ARCHIVE_DATE)"

image: ## build the Arch test image (ARCHIVE_DATE= for live mirrors)
	podman build --build-arg ARCHIVE_DATE=$(ARCHIVE_DATE) -t $(IMAGE) -f dev/Containerfile dev/

box: image ## create the distrobox from the image (idempotent)
	@if distrobox list --no-color 2>/dev/null | grep -qw '$(BOX)'; then \
		echo "distrobox '$(BOX)' exists (remove with: distrobox rm $(BOX))"; \
	else \
		distrobox create --yes --name $(BOX) --image localhost/$(IMAGE):latest; \
	fi

validate: ## all offline checks + live ALARM package resolution (inside the box)
	$(IN_BOX) ./scripts/validate.sh

validate-offline: ## same, without network stages
	$(IN_BOX) ./scripts/validate.sh --offline

nested-hypr: ## run the Hyprland session nested in your GNOME window
	$(IN_BOX) ./dev/nested.sh hyprland

nested-sway: ## run the sway session nested in your GNOME window
	$(IN_BOX) ./dev/nested.sh sway

bundle: ## write a git bundle (full history) for transfer
	git bundle create $(BUNDLE) --all
	git bundle verify $(BUNDLE)

check-board: ## run the prerequisite checker on the board over SSH (read-only)
	ssh $(BOARD) 'bash -s' < scripts/check-board.sh

deploy: ## copy the repo to the board (asks before copying)
	./scripts/deploy.sh $(BOARD)

install-board: ## deploy + run install.sh on the board (asks first; sudo prompts on the board)
	./scripts/deploy.sh $(BOARD) --install --profile all
