#!/bin/sh
# conduit pair — installs a conduit public key on this server and prints
# the connection details for your phone.
#
# Run it inside an SSH session to this server, from any computer:
#
#   curl -sSL https://raw.githubusercontent.com/Kakar13/conduit/main/scripts/conduit-pair.sh | sh -s -- '<your conduit public key>'
#
# Or paste conduit's inline pairing line (same install, no download).
#
# What it does — and nothing else:
#   1. appends the key to ~/.ssh/authorized_keys (idempotent, permissions fixed)
#   2. prints a conduit://connect link built from your session ($SSH_CONNECTION,
#      $USER) — no network calls, nothing leaves this machine
#   3. prints a QR of that link if `qrencode` is installed (optional)
set -eu

PUBKEY="${1:-}"

if [ -z "$PUBKEY" ]; then
    echo "usage: conduit-pair.sh '<your conduit public key>'" >&2
    echo "  (the full line conduit shows you: ecdsa-sha2-nistp256 AAAA… conduit@ios)" >&2
    exit 1
fi

case "$PUBKEY" in
    ecdsa-sha2-nistp256\ *|ssh-ed25519\ *|ssh-rsa\ *) ;;
    *) echo "conduit-pair: that doesn't look like an SSH public key." >&2; exit 1 ;;
esac

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
if grep -qF "$PUBKEY" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    echo "✓ key already present — nothing to do"
else
    echo "$PUBKEY" >> "$HOME/.ssh/authorized_keys"
    echo "✓ conduit key installed"
fi
chmod 600 "$HOME/.ssh/authorized_keys"

# Derive the connection details from this very SSH session — zero lookups.
user="$(id -un)"
host=""
port="22"
if [ -n "${SSH_CONNECTION:-}" ]; then
    # SSH_CONNECTION = client_ip client_port server_ip server_port
    host="$(printf '%s' "$SSH_CONNECTION" | cut -d' ' -f3)"
    port="$(printf '%s' "$SSH_CONNECTION" | cut -d' ' -f4)"
    [ -n "$port" ] || port="22"
else
    host="$(hostname 2>/dev/null || echo "")"
fi

if [ -z "$host" ]; then
    printf '\nOn your phone: connect as user %s (host: the address you SSH to).\n\n' "$user"
    exit 0
fi

link="conduit://connect?host=${host}&user=${user}&port=${port}"

printf '\nOn your phone, connect to:\n\n  %s@%s  (port %s)\n\nOr scan / open this link:\n\n  %s\n\n' \
    "$user" "$host" "$port" "$link"

if command -v qrencode >/dev/null 2>&1; then
    qrencode -t UTF8 "$link" || true
else
    echo "(install 'qrencode' on this server to also get a scannable QR code here)"
fi
