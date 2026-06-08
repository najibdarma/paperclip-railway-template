FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gosu curl ca-certificates && rm -rf /var/lib/apt/lists/*

# Install Claude CLI via npm (installs directly to /usr/local/bin in node image)
RUN npm install -g @anthropic-ai/claude-code

# Install Cursor agent, then relocate the whole install tree out of /root
# (mode 0700, unreachable by the non-root paperclip user) into /opt, preserving
# its internal directory layout. The agent entry point is a Node script that
# requires sibling files via __dirname, so copying just the binary breaks it
# ("Cannot find module '.../index.js'") — the full tree must move together.
RUN curl -fsSL https://cursor.com/install | bash && \
    mkdir -p /opt/cursor-agent && \
    for d in /root/.local /root/.cursor; do \
        if [ -d "$d" ]; then cp -aL "$d" /opt/cursor-agent/; fi; \
    done && \
    chmod -R a+rX /opt/cursor-agent && \
    AGENT_BIN=$(find /opt/cursor-agent \
        \( -name agent -o -name cursor-agent -o -name cursor \) \
        -type f 2>/dev/null | head -1) && \
    if [ -z "$AGENT_BIN" ]; then \
        echo "ERROR: Cursor agent binary not found after install. Installed executables:" && \
        find /opt/cursor-agent -type f 2>/dev/null | head -30; \
        exit 1; \
    fi && \
    echo "Cursor agent found at: $AGENT_BIN" && \
    AGENT_DIR=$(dirname "$AGENT_BIN") && \
    if [ ! -e "$AGENT_DIR/node" ]; then \
        ln -s "$(command -v node)" "$AGENT_DIR/node"; \
    fi && \
    ln -s "$AGENT_BIN" /usr/local/bin/agent

# Create a non-root user (required: Claude CLI refuses --dangerously-skip-permissions as root)
RUN groupadd -r paperclip && useradd -r -g paperclip -m -d /home/paperclip -s /bin/bash paperclip

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
RUN chown -R paperclip:paperclip /usr/local/bin/agent

# Copy and set up entrypoint (fixes volume mount ownership at runtime)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Railway injects PORT at runtime (default 3100)
ENV PORT=3100
EXPOSE 3100

# Entrypoint runs as root to fix volume permissions, then drops to paperclip user
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
