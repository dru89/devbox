@echo off
wsl env DEVBOX_HOST="%DEVBOX_HOST%" REMOTE_DIR="%REMOTE_DIR%" DEPLOY_USER="%DEPLOY_USER%" bash deploy.sh %*
