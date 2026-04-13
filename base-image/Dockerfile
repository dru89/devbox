FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install core packages
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    git \
    curl \
    wget \
    build-essential \
    ca-certificates \
    iproute2 \
    iptables \
    procps \
    htop \
    vim \
    nano \
    jq \
    unzip \
    stow \
    fzf \
    tig \
    && rm -rf /var/lib/apt/lists/*

# Install atuin (shell history sync)
RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh && \
    mv /root/.atuin/bin/atuin /usr/local/bin/atuin && \
    rm -rf /root/.atuin

# Install starship prompt
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install mise (formerly rtx) for Node/Python version management
# Install to /usr/local/bin so it's available to all users, not just root
RUN curl https://mise.run | sh && \
    mv /root/.local/bin/mise /usr/local/bin/mise && \
    echo 'eval "$(mise activate bash)"' >> /root/.bashrc && \
    echo 'eval "$(mise activate bash)"' >> /etc/profile.d/mise.sh

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config && \
    echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'AuthorizedKeysFile .ssh/authorized_keys' >> /etc/ssh/sshd_config && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Record installed packages — used by 'devbox upgrade' to detect system-level changes
RUN dpkg-query -W -f='${Package} ${Version}\n' | sort > /etc/devbox-manifest

# Copy CLAUDE.md into the image
COPY CLAUDE.md /root/CLAUDE.md
RUN ln -s /root/CLAUDE.md /workspace/CLAUDE.md

# Copy and install the idle detection sidecar
COPY idle-detect.sh /usr/local/bin/idle-detect
RUN chmod +x /usr/local/bin/idle-detect

# Install Claude Code helper script
COPY install-claude-code.sh /usr/local/bin/install-claude-code
RUN chmod +x /usr/local/bin/install-claude-code

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Idle timeout in minutes (0 = disabled)
ENV DEVBOX_IDLE_TIMEOUT=30

# Tailscale auth key (must be provided at runtime)
ENV TAILSCALE_AUTH_KEY=""

# Devbox name (set at runtime via --hostname)
ENV DEVBOX_NAME=""

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint"]
