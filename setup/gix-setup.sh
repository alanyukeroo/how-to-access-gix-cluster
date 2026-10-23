#!/bin/sh
# One-time laptop setup for GIX GPU devcontainers (macOS / Linux).
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/alanyukeroo/how-to-access-gix-cluster/main/setup/gix-setup.sh)"
# Creates an SSH key if you don't have one, adds "gix-login" and "gix-gpu" to
# ~/.ssh/config, and copies your key to gix-login (asks for your NetID password once).
# After this: VS Code -> Remote-SSH: Connect to Host -> gix-gpu.
set -e

printf "UW NetID: "
read -r NETID
[ -n "$NETID" ] || { echo "no NetID given"; exit 1; }

KEY="$HOME/.ssh/id_ed25519"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -f "$KEY" ]; then
    echo "creating SSH key $KEY (press Enter twice for no passphrase)"
    ssh-keygen -t ed25519 -f "$KEY"
fi

# optional for admins/pilots: GIX_NODE=gix-30292622 sh gix-setup.sh
PROXY="/usr/local/bin/gix-devjob"
[ -n "${GIX_NODE:-}" ] && PROXY="GIX_NODE=$GIX_NODE $PROXY"

CFG="$HOME/.ssh/config"
touch "$CFG"
chmod 600 "$CFG"
if grep -q '^Host gix-gpu$' "$CFG"; then
    echo "~/.ssh/config already has gix-gpu, leaving it alone"
else
    cat >> "$CFG" <<EOF

# --- GIX GPU cluster (added by gix-setup.sh) ---
Host gix-login
    HostName 10.155.32.7
    User $NETID
    IdentityFile $KEY
    # one shared login for VS Code's connections (each new login costs a NetID lookup)
    ControlMaster auto
    ControlPath ~/.ssh/gix-cm-%r@%h
    ControlPersist 10m

Host gix-gpu
    HostName gix-gpu-job
    User $NETID
    IdentityFile $KEY
    ProxyCommand ssh -q gix-login "$PROXY"
    # you can land on any of the GPU nodes, each with its own host key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 30
# --- end GIX ---
EOF
    echo "added gix-login and gix-gpu to $CFG"
fi

echo "copying your key to gix-login (enter your NetID password)"
ssh-copy-id -i "$KEY.pub" gix-login

echo
echo "Done. Test it:   ssh gix-gpu hostname"
echo "Then in VS Code: Remote-SSH: Connect to Host... -> gix-gpu"
