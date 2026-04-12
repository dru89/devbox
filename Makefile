# devbox — local client install
#
# Installs the devbox script and shell completions to your local machine
# so you can run devbox commands against a remote server via DEVBOX_HOST.
#
# Usage:
#   make install    — install devbox binary and zsh completion
#   make uninstall  — remove them
#
# Override PREFIX to change the install location (default: /usr/local):
#   make install PREFIX=~/.local

PREFIX  ?= /usr/local
BINDIR   = $(PREFIX)/bin
ZSH_SITE = $(PREFIX)/share/zsh/site-functions

.PHONY: install uninstall

install:
	install -d $(BINDIR)
	install -m 0755 scripts/devbox $(BINDIR)/devbox
	install -d $(ZSH_SITE)
	install -m 0644 scripts/devbox.zsh-completion $(ZSH_SITE)/_devbox
	@echo ""
	@echo "Installed:"
	@echo "  $(BINDIR)/devbox"
	@echo "  $(ZSH_SITE)/_devbox"
	@echo ""
	@echo "Next steps:"
	@echo ""
	@echo "  1. Set your server in ~/.bashrc or ~/.zshrc:"
	@echo "       export DEVBOX_HOST=yourserver"
	@echo ""
	@echo "  2. For bash tab completion, also add:"
	@echo "       source $(CURDIR)/scripts/devbox.bash-completion"
	@echo ""
	@echo "  3. For zsh tab completion, reload completions:"
	@echo "       autoload -U compinit && compinit"
	@echo ""

uninstall:
	rm -f $(BINDIR)/devbox $(ZSH_SITE)/_devbox
	@echo "Removed devbox."
