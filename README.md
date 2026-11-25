# oinit

First-time setup of a Debian-family Linux userland: Git settings, Neovim, gdb, olang and JupyterLab.

```
git clone https://github.com/osarv/oinit && cd oinit
./install.sh                # every target
./install.sh neovim gdb     # only these
```

The targets (`upgrade build git neovim gdb olang jupyter`) are described at the top of `install.sh`.

## Where it works

| Where | Notes |
| --- | --- |
| WSL2, Ubuntu or Debian, x86_64 | everything |
| Debian or Ubuntu, x86_64 | everything |
| Debian or Ubuntu, aarch64 (a Raspberry Pi) | everything but olang and Jupyter, which olang does not build for yet |
| OAgent's Android terminal (Debian arm64) | as the aarch64 line; runs as root or without sudo |

It looks at the machine rather than guessing: root (`id -u` is 0) uses `apt` as it is, `sudo` is used where present,
and with neither the `apt` steps are skipped with a note and Neovim goes into `~/.local`. The architecture comes from
`uname -m` and picks the Neovim release.

## With OAgent

Once OAgent is installed it keeps the package list and the dotfiles (`.gitconfig`, `.config/nvim`, ...) in step across
your devices. oinit is the bootstrap that gets a fresh machine to that point; it is not run again to keep things
current.
