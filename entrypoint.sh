#!/bin/bash
set -e

# Fix ownership of the Railway volume mount at /paperclip
# Railway mounts volumes as root, but we need the paperclip user to write to it
if [ -d "/paperclip" ]; then
  chown -R paperclip:paperclip /paperclip 2>/dev/null || true
fi

# Drop privileges and run the actual command as the paperclip user
exec gosu paperclip "$@"
