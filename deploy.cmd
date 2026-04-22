@echo off
wsl env DEVBOX_HOST="%DEVBOX_HOST%" REMOTE_DIR="%REMOTE_DIR%" DEPLOY_USER="%DEPLOY_USER%" SSH_AUTH_SOCK=/tmp/ssh-agent-1password.sock bash deploy.sh %*
