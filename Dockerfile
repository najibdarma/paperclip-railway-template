FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gosu curl ca-certificates git && rm -rf /var/lib/apt/lists/*

# Create a non-root user (required: Claude CLI refuses --dangerously-skip-permissions as root)
RUN groupadd -r paperclip && useradd -r -g paperclip -m -d /home/paperclip -s /bin/bash paperclip

# Install Claude CLI via npm (installs directly to /usr/local/bin in node image)
RUN npm install -g @anthropic-ai/claude-code

# Install Cursor agent as the paperclip user so it lands natively in
# /home/paperclip/.local, owned by paperclip, with exactly the layout and
# symlinks the installer expects. (Installing as root and relocating the
# files out of /root broke relative `require`s and symlink targets — the
# installer's own directory structure has to stay intact.)
RUN HOME=/home/paperclip gosu paperclip bash -c 'curl -fsSL https://cursor.com/install | bash' && \
    AGENT_BIN=$(find /home/paperclip/.local /home/paperclip/.cursor \
        \( -name agent -o -name cursor-agent -o -name cursor \) \
        2>/dev/null | head -1) && \
    if [ -z "$AGENT_BIN" ]; then \
        echo "ERROR: Cursor agent binary not found after install. Installed files:" && \
        find /home/paperclip/.local /home/paperclip/.cursor 2>/dev/null | head -30; \
        exit 1; \
    fi && \
    echo "Cursor agent found at: $AGENT_BIN"
ENV PATH="/home/paperclip/.local/bin:${PATH}"

# Create the paperclip home directory (Railway volume mount point)
RUN mkdir -p /paperclip && chown -R paperclip:paperclip /paperclip

WORKDIR /app

# Copy package files and install dependencies
COPY package.json ./
RUN npm install --omit=dev

# Copy application code
COPY . .

# Give ownership of everything to the non-root user
RUN chown -R paperclip:paperclip /app /home/paperclip
RUN chown -R paperclip:paperclip /usr/local/bin/claude

# Copy and set up entrypoint (fixes volume mount ownership at runtime)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Railway injects PORT at runtime (default 3100)
ENV PORT=3100
EXPOSE 3100

# Entrypoint runs as root to fix volume permissions, then drops to paperclip user
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
