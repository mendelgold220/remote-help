#!/bin/bash
# Remote help setup (macOS). Run as:  curl -fsSL <url> | bash -s -- <tailscale-auth-key>
# Does three things, all reversible in System Settings > General > Sharing (Remote Login) and by quitting Tailscale:
#   1. Installs Tailscale (private network between Mendel's Mac and this one; nothing exposed to the internet).
#   2. Adds Mendel's SSH key, valid only from Mendel's private address 100.105.45.83, expiring 2026-11-01.
#   3. Turns on Remote Login with passwords over SSH disabled.
#   4. Turns on Screen Sharing in "ask permission" mode: Mendel can only see or control the screen after
#      you click Share Screen on a prompt, each time. No password is stored or shared.
set -u

MENDEL_IP="100.105.45.83"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJVwZwlFroVC0HjxEyaeeCHTtEOp6ReBS0X6LaYD+Rrf mendel-uncle-investigation-20260915"
EXPIRES="20261101"
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
PKG_URL="https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg"
DRY="${DRY_RUN:-0}"

say() { printf '\n%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then echo "  (dry) $*"; else "$@" </dev/null; fi; }

main() {
  AUTHKEY="${1:-}"
  ME="$(whoami)"
  if [ -z "$AUTHKEY" ]; then say "Missing the setup code. Ask Mendel for the full command line."; exit 2; fi
  say "Setting up remote help for Mendel. You will be asked for your Mac password once."
  if [ "$DRY" != 1 ]; then sudo -v </dev/tty || { say "Password not accepted. Nothing was changed."; exit 1; }; fi

  say "[1/4] Tailscale"
  if [ ! -d /Applications/Tailscale.app ]; then
    run curl -fL -o /tmp/Tailscale.pkg "$PKG_URL" || { say "Download failed. Check the internet connection and run the command again."; exit 1; }
    if [ "$DRY" != 1 ] && ! pkgutil --check-signature /tmp/Tailscale.pkg 2>/dev/null | grep -q "Developer ID Installer: Tailscale"; then
      say "The downloaded Tailscale installer is not signed by Tailscale. Stopping; nothing was installed."; exit 1
    fi
    run sudo installer -pkg /tmp/Tailscale.pkg -target / || { say "Tailscale install failed."; exit 1; }
  fi
  run open -a Tailscale
  say "    If a prompt says Tailscale wants to add VPN configurations, click Allow."
  TSIP=""
  if [ "$DRY" != 1 ]; then
    for _ in $(seq 1 36); do
      sleep 5
      if "$TS" up --auth-key="$AUTHKEY" --accept-dns=false </dev/null >/dev/null 2>&1; then
        TSIP="$("$TS" ip -4 2>/dev/null | head -1)"; [ -n "$TSIP" ] && break
      fi
    done
    if [ -z "$TSIP" ]; then
      say "    Tailscale is not connected yet. Click Allow on any Tailscale prompt, then run the same command again."; exit 1
    fi
  else TSIP="100.0.0.0"; fi
  say "    Connected. Private address: $TSIP"

  say "[2/4] Mendel's key (only from $MENDEL_IP, expires $EXPIRES)"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  if ! grep -q "mendel-uncle-investigation" "$HOME/.ssh/authorized_keys"; then
    echo "from=\"$MENDEL_IP\",expiry-time=\"$EXPIRES\",no-agent-forwarding,no-port-forwarding,no-X11-forwarding $PUBKEY" >> "$HOME/.ssh/authorized_keys"
  fi
  grep -q "from=\"$MENDEL_IP\".*mendel-uncle-investigation" "$HOME/.ssh/authorized_keys" || { say "Could not write the key file. Stopping before Remote Login is turned on."; exit 1; }

  say "[3/4] SSH rules: only $ME from $MENDEL_IP, no passwords"
  CONF="AllowUsers $ME@$MENDEL_IP
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes"
  if [ "$DRY" = 1 ]; then echo "  (dry) write /etc/ssh/sshd_config.d/10-mendel-help.conf:"; echo "$CONF" | sed 's/^/        /'
  else
    run sudo mkdir -p /etc/ssh/sshd_config.d
    printf '%s\n' "$CONF" | sudo tee /etc/ssh/sshd_config.d/10-mendel-help.conf >/dev/null
    if ! sudo grep -q "^AllowUsers $ME@$MENDEL_IP\$" /etc/ssh/sshd_config.d/10-mendel-help.conf 2>/dev/null \
       || ! sudo grep -q "^PasswordAuthentication no\$" /etc/ssh/sshd_config.d/10-mendel-help.conf 2>/dev/null; then
      say "The SSH restriction file could not be written. Stopping before Remote Login is turned on; nothing is exposed."; exit 1
    fi
    sudo sshd -t 2>/dev/null || { say "SSH configuration check failed. Stopping before Remote Login is turned on."; exit 1; }
  fi

  say "[4/5] Remote Login on"
  run sudo launchctl enable system/com.openssh.sshd
  run sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  run sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
  run sudo systemsetup -setremotelogin on >/dev/null 2>&1 || true

  if [ "$DRY" != 1 ]; then
    sleep 2
    if nc -z -w 3 127.0.0.1 22 >/dev/null 2>&1; then SSHOK="on"; else SSHOK="OFF"; fi
  else SSHOK="(dry)"; fi

  say "[5/5] Screen Sharing on, ask-permission mode"
  KS="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
  run sudo "$KS" -configure -clientopts -setreqperm -reqperm yes -setvnclegacy -vnclegacy no >/dev/null 2>&1 || true
  run sudo launchctl enable system/com.apple.screensharing
  run sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
  run sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true
  if [ "$DRY" != 1 ]; then
    sleep 2
    if nc -z -w 3 127.0.0.1 5900 >/dev/null 2>&1; then VNCOK="on"; else VNCOK="OFF"; fi
  else VNCOK="(dry)"; fi

  say "=============================================="
  say "Done. Send this line to Mendel:   user $ME  at  $TSIP   (ssh $SSHOK, screen $VNCOK)"
  if [ "$SSHOK" = "OFF" ]; then
    say "One more click: System Settings > General > Sharing > turn ON Remote Login. Then tell Mendel."
  fi
  if [ "$VNCOK" = "OFF" ]; then
    say "One more click: System Settings > General > Sharing > turn ON Screen Sharing. Then tell Mendel."
  fi
  say "When Mendel asks to see your screen, a prompt appears; click Share Screen. You can stop it any time from the menu bar icon."
  say "To undo later: System Settings > General > Sharing > Remote Login and Screen Sharing off, then quit Tailscale."
}
main "$@"
