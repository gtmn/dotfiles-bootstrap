# dotfiles-bootstrap

Bootstraps a new Mac from my (private) dotfiles:

```
bash <(curl -fsSL https://raw.githubusercontent.com/gtmn/dotfiles-bootstrap/main/bootstrap.sh)
```

1. Installs Homebrew (incl. the Xcode Command Line Tools)
1. Creates an SSH key for this Mac and waits until it's added to GitHub
1. Clones the private dotfiles and runs their setup

Each step asks first; a re-run skips what's already done.

## Your own dotfiles

Works with any dotfiles repo on GitHub - set what differs before the command:

```
DOTFILES_REPO_URL=git@github.com:you/dotfiles DOTFILES_DIR=~/.dotfiles \
  bash <(curl -fsSL https://raw.githubusercontent.com/gtmn/dotfiles-bootstrap/main/bootstrap.sh)
```

| Variable | Default | What |
|---|---|---|
| `DOTFILES_REPO_URL` | `git@github.com:gtmn/dotfiles` | Repo to clone (SSH) |
| `DOTFILES_DIR` | `~/Developer/dotfiles` | Where to clone it |
| `SSH_KEY_NAME` | `id_ed25519_personal` | Key file in `~/.ssh` |
| `SSH_KEY_LABEL` | `personal` | Key comment: `<label>@<Mac> YYYY-MM` |

After the clone it runs the first setup script it finds in the repo: `dots/dots setup`, `setup/setup.sh`,
`install.sh`, `setup.sh`, `script/bootstrap`, `script/setup` (from the repo's folder). None found: it stops after
the clone. GitHub only (host keys, the "new SSH key" page).

Tests (throwaway homes, never touches this Mac): `./tests/test_bootstrap.sh`
