#!/usr/bin/env bash
# Test of bootstrap.sh in throwaway homes: ./tests/test_bootstrap.sh
# ssh, ssh-add, pbcopy and open are replaced by stubs: real ssh would read the REAL ~/.ssh/config
# (it ignores $HOME) and could log in with real keys; pbcopy/open would touch the real clipboard/browser.

BOOT="$(cd "$(dirname "$0")/.." && pwd)/bootstrap.sh"
S=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-test.XXXX")" && pwd -P)
pass=0 fail=0

check() { # <description> <command...>
    if "${@:2}" > /dev/null 2>&1; then echo "  ok   $1"; ((pass++)); else echo "  FAIL $1"; ((fail++)); fi
}

make_stubs() { # <dir> <ssh output>
    mkdir -p "$1"
    printf '#!/bin/sh\necho "%s" >&2\nexit 1\n' "$2" > "$1/ssh"
    printf '#!/bin/sh\necho "stub: $0 $*" >> "%s/stub-calls.log"\n' "$S" > "$1/ssh-add"
    cp "$1/ssh-add" "$1/pbcopy"; cp "$1/ssh-add" "$1/open"
    chmod +x "$1"/*
}

run_boot() { # <home> <stub dir> <extra env> [pattern=>answer ...]
    local home=$1 stubs=$2 env=$3; shift 3
    local script="set timeout 30; log_user 0; spawn env HOME=$home PATH=$stubs:$PATH SSH_AUTH_SOCK=/nonexistent $env bash $BOOT\n"
    local pair
    for pair in "$@"; do
        script+="expect {${pair%%=>*}} { send -- {${pair#*=>}} } timeout { puts \"TIMEOUT waiting for: ${pair%%=>*}\"; exit 2 }\n"
    done
    script+="expect eof; catch wait result; exit [lindex \$result 3]\n"
    printf "$script" > "$S/dialog.exp"
    expect "$S/dialog.exp"
}

echo "### Fresh Mac, key not yet added to GitHub"
H="$S/home1"; mkdir -p "$H"
make_stubs "$S/stubs-denied" "git@github.com: Permission denied (publickey)."
run_boot "$H" "$S/stubs-denied" "" \
    "Label for this Mac=>testmac\r" "Enter passphrase=>\r" "Enter same passphrase=>\r" \
    "Copy it to the clipboard=>n" "Open GitHub=>n" "test the connection again=>n"
rc=$?
check "stops with an error when the key isn't on GitHub yet" test "$rc" -eq 1
check "key ~/.ssh/id_ed25519_personal with comment personal@testmac" grep -q 'personal@testmac$' "$H/.ssh/id_ed25519_personal.pub"
check "Mac label shared with contexts.sh" grep -qx testmac "$H/.config/contexts/.machine"
check "~/.ssh is 700, config files 600" bash -c "[[ \$(stat -f %Lp '$H/.ssh') == 700 && \$(stat -f %Lp '$H/.ssh/config') == 600 && \$(stat -f %Lp '$H/.ssh/config.local') == 600 ]]"
check "config.local has github.com with the new key" bash -c "grep -q '^Host github.com' '$H/.ssh/config.local' && grep -q 'IdentityFile ~/.ssh/id_ed25519_personal' '$H/.ssh/config.local'"
check "~/.ssh/config includes config.local" grep -qx 'Include ~/.ssh/config.local' "$H/.ssh/config"
check "GitHub host keys pinned (3 key types)" test "$(grep -c '^github.com ' "$H/.ssh/known_hosts")" -eq 3
check "clipboard & browser untouched when declined" bash -c "! grep -qE 'pbcopy|open' '$S/stub-calls.log' 2> /dev/null"

echo; echo "### Re-run: existing key reused, nothing duplicated"
run_boot "$H" "$S/stubs-denied" "" "Copy it to the clipboard=>n" "Open GitHub=>n" "test the connection again=>n"
check "github.com entry not duplicated" test "$(grep -c '^Host github.com' "$H/.ssh/config.local")" -eq 1
check "host keys not duplicated" test "$(grep -c '^github.com ' "$H/.ssh/known_hosts")" -eq 3

echo; echo "### Key works -> clones the dotfiles (local test repo instead of GitHub)"
git init -q --bare "$S/remote.git"
git clone -q "$S/remote.git" "$S/seed" 2> /dev/null
mkdir -p "$S/seed/setup" && printf '#!/usr/bin/env bash\necho SETUP-RAN > "$HOME/setup-ran"\n' > "$S/seed/setup/setup.sh"
git -C "$S/seed" add -A && git -C "$S/seed" -c user.name=t -c user.email=t@t commit -qm init && git -C "$S/seed" push -q origin HEAD 2> /dev/null
make_stubs "$S/stubs-ok" "Hi tester! You've successfully authenticated, but GitHub does not provide shell access."
run_boot "$H" "$S/stubs-ok" "DOTFILES_REPO_URL=$S/remote.git" "Clone dotfiles=>y" "Run the dotfiles setup=>y"
rc=$?
check "exits cleanly" test "$rc" -eq 0
check "dotfiles cloned to ~/Developer/dotfiles" test -f "$H/Developer/dotfiles/setup/setup.sh"
check "setup.sh ran" grep -q SETUP-RAN "$H/setup-ran"

echo; echo "### Result: $pass passed, $fail failed"
if ((fail == 0)); then
    [[ -n $S && -d $S ]] && rm -rf -- "$S"
else
    echo "    (test files kept in $S)"
fi
((fail == 0))
