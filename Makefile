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
#
# On Windows (Git Bash / MSYS2), installs both the bash script and the
# PowerShell client. Override WIN_BIN to change the PowerShell install dir:
#   make install WIN_BIN=~/scripts

PREFIX   ?= /usr/local
BINDIR    = $(PREFIX)/bin
ZSH_SITE  = $(PREFIX)/share/zsh/site-functions

# Detect Windows: the OS env var is set to Windows_NT on all Windows environments
# (PowerShell, CMD, Git Bash, MSYS2) but not on macOS, Linux, or WSL.
ifeq ($(OS),Windows_NT)
WINDOWS := 1
else
WINDOWS :=
endif

.PHONY: install uninstall

ifdef WINDOWS

# Pass -WinBin only when the caller overrides WIN_BIN on the command line.
WIN_BIN_ARG = $(if $(WIN_BIN),-WinBin "$(WIN_BIN)",)

install:
	pwsh -NoLogo -NonInteractive -File scripts/install-client.ps1 $(WIN_BIN_ARG)

uninstall:
	pwsh -NoLogo -NonInteractive -File scripts/install-client.ps1 $(WIN_BIN_ARG) -Uninstall

else

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
	@echo "  2. For bash completion, add to ~/.bashrc:"
	@echo "       source $(CURDIR)/scripts/devbox.bash-completion"
	@echo ""
	@echo "  3. For zsh completion, reload completions:"
	@echo "       autoload -U compinit && compinit"
	@echo ""

uninstall:
	rm -f $(BINDIR)/devbox $(ZSH_SITE)/_devbox
	@echo "Removed devbox."

endif
