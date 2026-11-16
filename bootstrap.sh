#!/usr/bin/env bash

# ====================================================================================================
# bootstrap.sh - Bootstrap a new Mac from the private dotfiles repo
#
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/gtmn/dotfiles-bootstrap/main/bootstrap.sh)
#
# Installs Homebrew, creates this Mac's SSH key for GitHub, clones the private dotfiles and runs their
# setup. Self-contained on purpose: nothing else is downloaded before the SSH key exists.
#
# Other dotfiles repos: set these before the command (defaults: the gtmn dotfiles)
#   DOTFILES_REPO_URL  repo to clone over SSH            DOTFILES_DIR   where to clone it
#   SSH_KEY_NAME       key file in ~/.ssh                SSH_KEY_LABEL  key comment: <label>@<Mac> YYYY-MM
# The setup that runs after the clone: the first of SETUP_CANDIDATES found in the repo.
# ====================================================================================================

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-git@github.com:gtmn/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Developer/dotfiles}"
SSH_KEY_NAME="${SSH_KEY_NAME:-id_ed25519_personal}" # same key name as the "personal" context
SSH_KEY_LABEL="${SSH_KEY_LABEL:-personal}"
TILDE='~' # for ${path/#$HOME/$TILDE}: a literal ~ there works in bash 3.2 but becomes $HOME again in bash 5
SSH_KEY_FILE="$HOME/.ssh/$SSH_KEY_NAME"
MACHINE_FILE="$HOME/.config/contexts/.machine"     # Mac label, shared with dots/lib/contexts.sh (dots repos only)

# Setup entry points, first found wins: dots (this tool), its old layout, then common names in other repos
SETUP_CANDIDATES=(dots/dots setup/setup.sh install.sh setup.sh script/bootstrap script/setup)

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

# Mac label from the key comment (<label>@<Mac> YYYY-MM) - for a key made by an earlier run
machine_from_key() {
    local comment
    comment=$(awk '{ print $3 }' "$SSH_KEY_FILE.pub" 2> /dev/null)
    [[ $comment == *@* ]] && echo "${comment#*@}"
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
    echo "Using existing SSH key ${SSH_KEY_FILE/#$HOME/$TILDE}"
else
    machine=$(ask_for_value "Label for this Mac (shown in the SSH key comment)" "$(hostname -s)")

    ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -C "$SSH_KEY_LABEL@$machine $(date +%Y-%m)" || abort "Could not create the SSH key."
    ssh-add --apple-use-keychain "$SSH_KEY_FILE"
fi

# Machine-specific hosts live in config.local, which the dotfiles' ~/.ssh/config includes later
if ! grep -qs "IdentityFile ${SSH_KEY_FILE/#$HOME/$TILDE}" "$HOME/.ssh/config.local"; then
    printf 'Host github.com\n    IdentityFile %s\n' "${SSH_KEY_FILE/#$HOME/$TILDE}" >> "$HOME/.ssh/config.local"
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
    echo "Title: $(cut -d' ' -f3- "$SSH_KEY_FILE.pub")  (Mac & month: tells this key apart from older ones)"
    confirm_yes "Copy it to the clipboard?" && pbcopy < "$SSH_KEY_FILE.pub"
    confirm_yes "Open GitHub's 'new SSH key' page?" && open "https://github.com/settings/ssh/new"
    confirm "Added the key - test the connection again [y/n]? " || abort "Add the SSH key, then re-run this script."
done
echo "SSH connection to GitHub works"

# ====================================================================================================
# Clone the private dotfiles & run their setup
# ====================================================================================================

if [[ -d "$DOTFILES_DIR/.git" ]]; then
    confirm_yes "Pull latest dotfiles in ${DOTFILES_DIR/#$HOME/$TILDE}?" && git -C "$DOTFILES_DIR" pull
else
    confirm_yes "Clone dotfiles to ${DOTFILES_DIR/#$HOME/$TILDE}?" &&
        mkdir -p "$(dirname "$DOTFILES_DIR")" &&
        git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
fi

[[ -d "$DOTFILES_DIR/.git" ]] || abort "Dotfiles not found in $DOTFILES_DIR"

# dots asks contexts.sh for the Mac label - hand over the one the SSH key was made with
if [[ -x "$DOTFILES_DIR/dots/dots" && ! -s "$MACHINE_FILE" ]]; then
    machine=${machine:-$(machine_from_key)}
    [[ -n $machine ]] && mkdir -p -m 700 "$(dirname "$MACHINE_FILE")" && echo "$machine" > "$MACHINE_FILE"
fi

setup=""
for candidate in "${SETUP_CANDIDATES[@]}"; do
    [[ -f "$DOTFILES_DIR/$candidate" ]] && setup=$candidate && break
done

case "$setup" in
    "")
        echo "Cloned to ${DOTFILES_DIR/#$HOME/$TILDE} - no setup script found (${SETUP_CANDIDATES[*]}): run its setup yourself"
        ;;
    dots/dots)
        confirm_yes "Run the dotfiles setup (dots setup)?" && "$DOTFILES_DIR/dots/dots" setup
        ;;
    *)
        if confirm_yes "Run the dotfiles setup ($setup)?"; then
            if [[ -x "$DOTFILES_DIR/$setup" ]]; then
                (cd "$DOTFILES_DIR" && "./$setup")
            else
                (cd "$DOTFILES_DIR" && bash "./$setup")
            fi
        fi
        ;;
esac
