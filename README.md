# remote-help

One-line, reversible remote-help setup for a family Mac. Installs Tailscale, adds one SSH key restricted to one private address, turns on Remote Login with passwords disabled. Undo in System Settings > General > Sharing > Remote Login, then quit Tailscale.

Run (the person helping supplies the code at the end):

    curl -fsSL https://raw.githubusercontent.com/mendelgold220/remote-help/main/setup.sh | bash -s -- <code>

Notes:
- The code at the end is a single-use Tailscale auth key. It is consumed when the Mac joins and should be revoked in the Tailscale admin console afterwards; it will also appear in the Terminal history of the Mac it was run on, which is harmless once revoked.
- The Tailscale installer's Developer ID signature is verified before installation.
- Remote Login is only turned on after the SSH restriction file is confirmed in place and `sshd -t` passes; any failure stops the script before anything is exposed.
