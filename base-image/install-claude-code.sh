#!/usr/bin/env bash
# Install Claude Code CLI inside the devbox.
# Run this once after the container is created.

set -euo pipefail

echo "Installing Claude Code..."

# Ensure mise-managed node is available, or fall back to system npm/npx
if command -v mise &>/dev/null; then
    eval "$(mise activate bash)" 2>/dev/null || true
fi

if ! command -v npm &>/dev/null; then
    echo ""
    echo "Node.js is not installed. Install it first with mise:"
    echo "  mise use node@lts"
    echo "  eval \"\$(~/.local/bin/mise activate bash)\""
    echo ""
    echo "Then re-run: install-claude-code"
    exit 1
fi

npm install -g @anthropic-ai/claude-code

echo ""
echo "Claude Code installed. Run: claude"
