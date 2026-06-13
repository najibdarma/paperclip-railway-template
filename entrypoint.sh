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

# Migrates any pre-existing config at $home_path into $persist_path (first
# run only) and replaces $home_path with a symlink to it. Shared by the
# dir/file variants below — they differ only in how $persist_path gets
# created when there's nothing to migrate.
relink_into_persist_dir() {
  local home_path="$1"
  local persist_path="$2"

  mkdir -p "$(dirname "$persist_path")"

  if [ -e "$home_path" ] && [ ! -L "$home_path" ]; then
    rm -rf "$persist_path"
    mv "$home_path" "$persist_path"
  fi

  mkdir -p "$(dirname "$home_path")"
  rm -rf "$home_path"
  ln -s "$persist_path" "$home_path"
}

# Directories must exist at $persist_path *before* symlinking — otherwise
# the symlink dangles and tools fail with ENOENT trying to create files
# inside it (e.g. opening ~/.claude/settings.json when ~/.claude points to
# a directory that was never created).
link_dir_into_persist_dir() {
  local rel_path="$1"
  local home_path="$PAPERCLIP_HOME_DIR/$rel_path"
  local persist_path="$PERSIST_DIR/$rel_path"

  relink_into_persist_dir "$home_path" "$persist_path"
  mkdir -p "$persist_path"
}

# Files are safe to leave absent: opening a dangling symlink with O_CREAT
# creates the target file on first write, as long as its parent dir exists
# (which relink_into_persist_dir guarantees via mkdir -p "$(dirname ...)").
link_file_into_persist_dir() {
  local rel_path="$1"
  relink_into_persist_dir "$PAPERCLIP_HOME_DIR/$rel_path" "$PERSIST_DIR/$rel_path"
}

link_dir_into_persist_dir ".claude"
link_file_into_persist_dir ".claude.json"
link_dir_into_persist_dir ".cursor"

chown -R paperclip:paperclip "$PERSIST_DIR" "$PAPERCLIP_HOME_DIR"

# Pre-create cursor-agent's XDG config dir with the owner/mode it expects
# (paperclip:paperclip, 0700). `cursor login` stat()s this dir and only
# calls chmod() if the mode differs — left to create it itself as paperclip,
# that chmod() fails with "EPERM: operation not permitted, chmod
# '/home/paperclip/.config/cursor'" under Railway's sandboxed filesystem.
# Pre-setting the mode here means cursor-agent sees it's already correct
# and skips the chmod call.
mkdir -p "$PAPERCLIP_HOME_DIR/.config/cursor"
chmod 700 "$PAPERCLIP_HOME_DIR/.config/cursor"
chown -R paperclip:paperclip "$PAPERCLIP_HOME_DIR/.config"

# Install gsd-core (GSD skills/commands for Claude Code and Cursor) on first
# boot only. It installs into ~/.claude and ~/.cursor, both of which are
# symlinked onto the /paperclip volume above, so the install persists across
# redeploys and this check skips it on every later boot.
GSD_CLAUDE_MARKER="$PAPERCLIP_HOME_DIR/.claude/gsd-install-state.json"
GSD_CURSOR_MARKER="$PAPERCLIP_HOME_DIR/.cursor/gsd-install-state.json"
if [ ! -f "$GSD_CLAUDE_MARKER" ] || [ ! -f "$GSD_CURSOR_MARKER" ]; then
  echo "Installing gsd-core..."
  gosu paperclip env HOME="$PAPERCLIP_HOME_DIR" GSD_PORTABLE_HOOKS=1 \
    npx -y @opengsd/gsd-core@latest --claude --cursor --global \
    || echo "gsd-core install failed, continuing without it"
  chown -R paperclip:paperclip "$PERSIST_DIR"
else
  echo "gsd-core already installed, skipping"
fi

# Install caveman (token-compression skill) for Claude Code and Cursor on
# first boot only. It writes hooks/settings into ~/.claude and rule files
# into ~/.cursor, both of which are symlinked onto the /paperclip volume
# above, so the install persists across redeploys and this check skips it
# on every later boot.
CAVEMAN_MARKER="$PAPERCLIP_HOME_DIR/.claude/.caveman-active"
if [ ! -f "$CAVEMAN_MARKER" ]; then
  echo "Installing caveman..."
  gosu paperclip env HOME="$PAPERCLIP_HOME_DIR" bash -c \
    'curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash -s -- --all --with-hooks --non-interactive --force' \
    || echo "caveman install failed, continuing without it"
  chown -R paperclip:paperclip "$PERSIST_DIR"
else
  echo "caveman already installed, skipping"
fi

# Drop privileges and run the actual command as the paperclip user
exec gosu paperclip "$@"
