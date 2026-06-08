#!/bin/bash
set -e

PAPERCLIP_HOME_DIR="/home/paperclip"
PERSIST_DIR="/paperclip/agent-config"

# Fix ownership of the Railway volume mount at /paperclip
# Railway mounts volumes as root, but we need the paperclip user to write to it
if [ -d "/paperclip" ]; then
  chown -R paperclip:paperclip /paperclip 2>/dev/null || true
fi

# Persist Claude and Cursor agent config/credentials across redeploys by
# storing them on the /paperclip volume and symlinking them into the
# paperclip user's home directory. Without this, logins and settings would
# be lost every time the container is rebuilt.
mkdir -p "$PERSIST_DIR"

link_into_persist_dir() {
  local rel_path="$1"
  local home_path="$PAPERCLIP_HOME_DIR/$rel_path"
  local persist_path="$PERSIST_DIR/$rel_path"

  mkdir -p "$(dirname "$persist_path")"

  # First run: migrate any existing config into the persisted volume
  if [ -e "$home_path" ] && [ ! -L "$home_path" ]; then
    rm -rf "$persist_path"
    mv "$home_path" "$persist_path"
  fi

  mkdir -p "$(dirname "$home_path")"
  rm -rf "$home_path"
  ln -s "$persist_path" "$home_path"
}

for path in ".claude" ".claude.json" ".cursor"; do
  link_into_persist_dir "$path"
done

chown -R paperclip:paperclip "$PERSIST_DIR" "$PAPERCLIP_HOME_DIR"

# Drop privileges and run the actual command as the paperclip user
exec gosu paperclip "$@"
