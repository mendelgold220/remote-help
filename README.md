# remote-help

One-line, reversible remote-help setup for a family Mac. Installs Tailscale, adds one SSH key restricted to one private address, turns on Remote Login with passwords disabled. Undo in System Settings > General > Sharing > Remote Login, then quit Tailscale.

Run (the person helping supplies the code at the end):

    curl -fsSL https://raw.githubusercontent.com/mendelgold220/remote-help/main/setup.sh | bash -s -- <code>
