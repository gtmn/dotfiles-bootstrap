#!/usr/bin/env bash

# ====================================================================================================
# bootstrap.sh - Bootstrap a new Mac from the private dotfiles repo
#
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/gtmn/dotfiles-bootstrap/main/bootstrap.sh)
#
# Installs Homebrew, creates this Mac's SSH key for GitHub, clones the private dotfiles and runs their
# setup. Self-contained on purpose: nothing else is downloaded before the SSH key exists.
# ====================================================================================================

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-git@github.com:gtmn/dotfiles}"
DOTFILES_DIR="$HOME/Developer/dotfiles"
SSH_KEY_FILE="$HOME/.ssh/id_ed25519_personal"     # same key name as the "personal" context
MACHINE_FILE="$HOME/.config/contexts/.machine"     # Mac label, shared with scripts/contexts.sh

# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]; then
    printf "Bash is required to interpret this script.\n" >&2
    exit 1
fi

# ====================================================================================================
# Functions
# ====================================================================================================

abort() {
    printf "%s\n" "$@" >&2
    exit 1
}

# Single keypress y/n from the terminal; $2 = return value on enter (empty: enter is ignored)
confirm() {
    local prompt="$1" enter_return=$2 reply

    # No terminal: never guess an answer - stop with an error
    { : < /dev/tty; } 2> /dev/null || abort "Can't ask without a terminal: $prompt"

    while true; do
        printf '%s' "$prompt" > /dev/tty
        IFS= read -rn1 reply < /dev/tty
        [[ -n $reply ]] && printf '\n' > /dev/tty
        case "$reply" in
            Y | y) return 0 ;;
            N | n) return 1 ;;
            '') [[ -n $enter_return ]] && return "$enter_return" ;;
        esac
    done
}

confirm_yes() {
    confirm "$* [Y/n]? " 0
}

ask_for_value() { # <question> <default>
    local input

    IFS= read -erp "$1 ($2): " input < /dev/tty
    echo "${input:-$2}"
}

# Trust GitHub's SSH host keys as published via its HTTPS API (instead of trusting the first connection)
add_github_host_keys() {
    local meta key i=0

    meta=$(curl -fsSL https://api.github.com/meta) || return 1
    while key=$(plutil -extract "ssh_keys.$i" raw -o - - <<< "$meta" 2> /dev/null); do
        grep -qF "$key" "$HOME/.ssh/known_hosts" 2> /dev/null || echo "github.com $key" >> "$HOME/.ssh/known_hosts"
        ((i++))
    done
    ((i > 0))
}

github_auth_works() {
    ssh -T -o BatchMode=yes git@github.com 2>&1 | grep -q "successfully authenticated"
}

# ====================================================================================================
# Homebrew (also installs the Xcode Command Line Tools, which provide git)
# ====================================================================================================

if ! command -v brew &> /dev/null && [[ ! -x /opt/homebrew/bin/brew ]]; then
    confirm_yes "Install Homebrew?" &&
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew is already installed..."
fi

[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
command -v brew &> /dev/null || abort "Homebrew is required to continue."

# ====================================================================================================
# SSH key for GitHub - one per Mac, never copied between Macs
# ====================================================================================================

mkdir -p -m 700 "$HOME/.ssh"

if [[ -f "$SSH_KEY_FILE" ]]; then
    echo "Using existing SSH key ${SSH_KEY_FILE/#$HOME/~}"
else
    machine=$(ask_for_value "Label for this Mac (shown in the SSH key comment)" "$(hostname -s)")
    mkdir -p -m 700 "$(dirname "$MACHINE_FILE")" && echo "$machine" > "$MACHINE_FILE"

    ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -C "personal@$machine" || abort "Could not create the SSH key."
    ssh-add --apple-use-keychain "$SSH_KEY_FILE"
fi

# Machine-specific hosts live in config.local, which the dotfiles' ~/.ssh/config includes later
if ! grep -qs "IdentityFile ${SSH_KEY_FILE/#$HOME/~}" "$HOME/.ssh/config.local"; then
    printf 'Host github.com\n    IdentityFile %s\n' "${SSH_KEY_FILE/#$HOME/~}" >> "$HOME/.ssh/config.local"
fi
if [[ ! -e "$HOME/.ssh/config" ]]; then
    echo "Include ~/.ssh/config.local" > "$HOME/.ssh/config"
fi
chmod 600 "$HOME/.ssh/config" "$HOME/.ssh/config.local"

add_github_host_keys || echo "WARN Could not fetch GitHub's SSH host keys, ssh will ask on first connect"

until github_auth_works; do
    echo
    echo "Add this public key to GitHub (Settings -> SSH and GPG keys):"
    cat "$SSH_KEY_FILE.pub"
    confirm_yes "Copy it to the clipboard?" && pbcopy < "$SSH_KEY_FILE.pub"
    confirm_yes "Open GitHub's 'new SSH key' page?" && open "https://github.com/settings/ssh/new"
    confirm "Added the key - test the connection again [y/n]? " || abort "Add the SSH key, then re-run this script."
done
echo "SSH connection to GitHub works"

# ====================================================================================================
# Clone the private dotfiles & run their setup
# ====================================================================================================

if [[ -d "$DOTFILES_DIR/.git" ]]; then
    confirm_yes "Pull latest dotfiles in ${DOTFILES_DIR/#$HOME/~}?" && git -C "$DOTFILES_DIR" pull
else
    confirm_yes "Clone dotfiles to ${DOTFILES_DIR/#$HOME/~}?" &&
        mkdir -p "$(dirname "$DOTFILES_DIR")" &&
        git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
fi

[[ -f "$DOTFILES_DIR/setup/setup.sh" ]] || abort "Dotfiles not found in $DOTFILES_DIR"
confirm_yes "Run the dotfiles setup?" && bash "$DOTFILES_DIR/setup/setup.sh"
