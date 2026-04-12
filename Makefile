# devbox — local client install
#
# Installs the devbox script and shell completions to your local machine
# so you can run devbox commands against a remote server via DEVBOX_HOST.
#
# Usage:
#   make install    — install devbox binary and shell completions
#   make uninstall  — remove them
#
# Override PREFIX to change the install location (default: /usr/local):
#   make install PREFIX=~/.local

PREFIX  ?= /usr/local
BINDIR   = $(PREFIX)/bin
ZSH_SITE = $(PREFIX)/share/zsh/site-functions

# Bash completion: prefer Homebrew's auto-load directory if brew is available
BREW_PREFIX  := $(shell brew --prefix 2>/dev/null)
BASH_COMP_DIR := $(if $(BREW_PREFIX),$(BREW_PREFIX)/etc/bash_completion.d,$(PREFIX)/etc/bash_completion.d)

.PHONY: install uninstall

install:
	install -d $(BINDIR)
	install -m 0755 scripts/devbox $(BINDIR)/devbox
	install -d $(ZSH_SITE)
	install -m 0644 scripts/devbox.zsh-completion $(ZSH_SITE)/_devbox
	install -d $(BASH_COMP_DIR)
	install -m 0644 scripts/devbox.bash-completion $(BASH_COMP_DIR)/devbox
	@echo ""
	@echo "Installed:"
	@echo "  $(BINDIR)/devbox"
	@echo "  $(ZSH_SITE)/_devbox"
	@echo "  $(BASH_COMP_DIR)/devbox"
	@echo ""
	@echo "Next steps:"
	@echo ""
	@echo "  1. Set your server in ~/.bashrc or ~/.zshrc:"
	@echo "       export DEVBOX_HOST=yourserver"
	@echo ""
	@if [ -n "$(BREW_PREFIX)" ]; then \
		echo "  2. For bash completion to auto-load, ensure bash-completion@2 is set up:"; \
		echo "       brew install bash-completion@2"; \
		echo "     Then add to ~/.bashrc if not already present:"; \
		echo "       [[ -r \"$(BREW_PREFIX)/etc/profile.d/bash_completion.sh\" ]] && . \"$(BREW_PREFIX)/etc/profile.d/bash_completion.sh\""; \
	else \
		echo "  2. For bash completion, add to ~/.bashrc:"; \
		echo "       source $(BASH_COMP_DIR)/devbox"; \
	fi
	@echo ""
	@echo "  3. For zsh completion, reload completions:"
	@echo "       autoload -U compinit && compinit"
	@echo ""

uninstall:
	rm -f $(BINDIR)/devbox $(ZSH_SITE)/_devbox $(BASH_COMP_DIR)/devbox
	@echo "Removed devbox."
