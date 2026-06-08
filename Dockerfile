FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gosu curl ca-certificates && rm -rf /var/lib/apt/lists/*

# Install Claude CLI via npm (installs directly to /usr/local/bin in node image)
RUN npm install -g @anthropic-ai/claude-code

# Install Cursor agent and copy to /usr/local/bin
RUN curl -fsSL https://cursor.com/install | bash
ENV PATH="/root/.local/bin:${PATH}"
RUN AGENT_BIN=$(find /root/.local/bin /usr/local/bin -name agent -type f 2>/dev/null | head -1) && \
    [ -n "$AGENT_BIN" ] && cp "$AGENT_BIN" /usr/local/bin/agent || true

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

# Copy and set up entrypoint (fixes volume mount ownership at runtime)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Railway injects PORT at runtime (default 3100)
ENV PORT=3100
EXPOSE 3100

# Entrypoint runs as root to fix volume permissions, then drops to paperclip user
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
