#!/bin/bash
# First-time setup of a Debian-family Linux userland, the same on each of:
#   - WSL2 (Ubuntu or Debian, x86_64)
#   - a plain Debian or Ubuntu (x86_64 or aarch64, a Raspberry Pi for one)
#   - OAgent's Android terminal (a Debian arm64 userland, as root or without sudo)
#
# ./install.sh                 every target below, in this order
# ./install.sh TARGET...       only those, in the order given
#
# What it finds out, and does with it:
#   privilege   root (id -u is 0): apt as it is; sudo present: apt through sudo; neither: the apt steps are skipped
#               with a note, and Neovim goes into ~/.local instead of /opt
#   arch        uname -m, x86_64 or aarch64 (arm64): picks the Neovim release; olang is built on x86_64 only
#
#   upgrade   the system's packages updated and upgraded, the unused removed (apt)
#   build     gcc, make, curl and ca-certificates (apt)
#   git       git, and its global settings: name, email, master as the default branch, push sets the upstream
#   neovim    the newest official Neovim release for the arch (nvim-linux-x86_64 or nvim-linux-arm64): in /opt/nvim
#             linked from /usr/local/bin with root or sudo (apt's removed, too old for olang's completion, which
#             needs 0.11), else in ~/.local/opt/nvim linked from ~/.local/bin; and init.lua into ~/.config/nvim
#             (an old init.vim there removed: Neovim refuses to start with both)
#   gdb       gdb, and gdbinit into ~/.gdbinit
#   olang     olang built from its own checkout (~/.local/src/olang, always master) and installed into ~/.local,
#             with clang and the libraries it needs; its prompt edits in vi mode (x86_64 Linux only, skipped
#             elsewhere)
#   jupyter   JupyterLab, with olang as a kernel (after olang; skipped where olang is)

all="upgrade build git neovim gdb olang jupyter"
cd "$(dirname "$0")" || exit 1

arch=$(uname -m)
case "$arch" in
    x86_64) nvim_arch=x86_64 ;;
    aarch64 | arm64) nvim_arch=arm64 ;;
    *) nvim_arch= ;;
esac

if [ "$(id -u)" = 0 ]; then
    priv=root
elif command -v sudo > /dev/null 2>&1; then
    priv=sudo
else
    priv=none
fi

note() { echo "install.sh: $*" >&2; }

# run a command as root: directly, or through sudo
as_root() {
    case "$priv" in
        root) "$@" ;;
        sudo) sudo "$@" ;;
        *) return 1 ;;
    esac
}

# apt as root; skipped, with a note, where it cannot run
apt_() {
    if ! command -v apt > /dev/null 2>&1; then
        note "no apt here - 'apt $*' skipped"
        return 0
    fi
    if [ "$priv" = none ]; then
        note "not root and no sudo - 'apt $*' skipped"
        return 0
    fi
    as_root env DEBIAN_FRONTEND=noninteractive apt -y "$@"
}

olang_host() { [ "$(uname -s) $arch" = "Linux x86_64" ]; }

upgrade() {
    apt_ update
    apt_ autoremove
    apt_ upgrade
}

build() {
    apt_ install gcc make curl ca-certificates
}

git_() {
    command -v git > /dev/null 2>&1 || apt_ install git
    git config --global init.defaultBranch master
    git config --global user.email "oscar.arvidsson@protonmail.com"
    git config --global user.name "Oscar Arvidsson"
    git config --global push.autoSetupRemote true
}

neovim() {
    if [ "$(uname -s)" != Linux ] || [ -z "$nvim_arch" ]; then
        note "no Neovim release for $(uname -s) $arch - skipped"
        return 0
    fi
    command -v curl > /dev/null 2>&1 || apt_ install curl ca-certificates
    command -v curl > /dev/null 2>&1 || { note "neovim needs curl"; return 1; }
    name=nvim-linux-$nvim_arch
    tmp=$(mktemp -d) || return 1
    curl -fsSL -o "$tmp/nvim.tar.gz" "https://github.com/neovim/neovim/releases/latest/download/$name.tar.gz" || { rm -rf "$tmp"; return 1; }
    if [ "$priv" != none ]; then
        # system-wide: /usr/local/bin comes before /usr/bin; apt's neovim removed
        as_root rm -rf /opt/nvim "/opt/$name"
        as_root tar -xzf "$tmp/nvim.tar.gz" -C /opt && as_root mv "/opt/$name" /opt/nvim || { rm -rf "$tmp"; return 1; }
        as_root ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
        dpkg -s neovim > /dev/null 2>&1 && as_root apt -y remove neovim
        # what an install into the home directory left
        rm -rf ~/.local/opt/nvim
        [ -L ~/.local/bin/nvim ] && rm -f ~/.local/bin/nvim
    else
        note "not root and no sudo - Neovim goes into ~/.local (~/.local/bin must be on PATH)"
        mkdir -p ~/.local/opt ~/.local/bin
        rm -rf ~/.local/opt/nvim "$HOME/.local/opt/$name"
        tar -xzf "$tmp/nvim.tar.gz" -C ~/.local/opt && mv "$HOME/.local/opt/$name" ~/.local/opt/nvim || { rm -rf "$tmp"; return 1; }
        ln -sf ~/.local/opt/nvim/bin/nvim ~/.local/bin/nvim
    fi
    rm -rf "$tmp"
    hash -r
    "$(command -v nvim || echo ~/.local/bin/nvim)" --version | head -1
    mkdir -p ~/.config/nvim
    rm -f ~/.config/nvim/init.vim
    cp init.lua ~/.config/nvim/init.lua
}

gdb_() {
    command -v gdb > /dev/null 2>&1 || apt_ install gdb
    cp gdbinit ~/.gdbinit
}

olang() {
    if ! olang_host; then
        note "olang is built on x86_64 Linux only, this is $(uname -s) $arch - skipped"
        return 0
    fi
    # clang 18 or newer with its LTO plugin, xz, libffi and the C headers
    apt_ install clang-18 llvm-18-linker-tools xz-utils libffi-dev libc6-dev
    # its own checkout, always master: a working checkout elsewhere (~/olang) is never touched
    src=~/.local/src/olang
    if [ -d "$src/.git" ]; then
        git -C "$src" fetch --depth 1 origin master && git -C "$src" reset --hard origin/master
    else
        git clone --depth 1 --branch master https://github.com/osarv/olang "$src"
    fi
    make -C "$src" || return 1
    # the olang prompt edits in vi mode
    grep -qxF 'export OLANG_EDIT=vi' ~/.bashrc 2> /dev/null || echo 'export OLANG_EDIT=vi' >> ~/.bashrc
}

jupyter() {
    if ! olang_host; then
        note "jupyter needs olang, which is not built on $(uname -s) $arch - skipped"
        return 0
    fi
    if [ ! -x ~/.local/bin/olang ]; then
        note "jupyter needs olang installed first (./install.sh olang jupyter)"
        return 1
    fi
    apt_ install pipx
    command -v pipx > /dev/null 2>&1 || { note "jupyter needs pipx"; return 1; }
    pipx install jupyterlab
    ~/.local/bin/olang serve jupyter -install
}

targets="${*:-$all}"
for t in $targets; do
    case " $all " in
        *" $t "*) ;;
        *) note "unknown target '$t' - one of: $all"; exit 1 ;;
    esac
done
for t in $targets; do
    echo "== $t"
    case "$t" in
        git) git_ ;;
        gdb) gdb_ ;;
        *) "$t" ;;
    esac || { note "$t failed"; exit 1; }
done
