# dotfiles-bootstrap

Bootstraps a new Mac from my (private) dotfiles:

```
bash <(curl -fsSL https://raw.githubusercontent.com/gtmn/dotfiles-bootstrap/main/bootstrap.sh)
```

1. Installs Homebrew (incl. the Xcode Command Line Tools)
1. Creates an SSH key for this Mac and waits until it's added to GitHub
1. Clones the private dotfiles and runs their setup
