# NixOS configurations

Flake-based NixOS configurations for my machines.

## Hosts

| Host | Machine | nixpkgs |
|------|---------|---------|
| `procyon-nixos` | Dell Precision 5490 work laptop (GNOME) | nixos-26.05 |
| `miaudesk-nixos` | NixOS on WSL inside a Windows desktop | nixos-25.11 |
| `miaupad-nixos` | Lenovo ThinkPad T440s (awesome wm) | nixos-25.11 |
| `miaucloud-nixos` | DigitalOcean droplet, public web server | nixos-25.11 |

## Layout

Each host is composed in `flake.nix` from shared `common/` modules plus its
own directory (hardware scan results and host-specific configuration):

- `common/base.nix` — cli basics for every machine
- `common/graphical.nix` — desktop basics
- `common/workstation.nix` — dev machine setup: podman, nix-ld, python environment, common tooling (procyon, miaudesk)
- `common/agents.nix` — AI coding agent CLIs and safepilot build-time configuration (procyon, miaudesk)
- `common/safepilot.nix` — module for the sandboxed agent container launcher
- `common/pkgs/` — package definitions used by the modules above

## Usage

Every machine has this repo cloned at `/etc/nixos`. To update a machine:

```
cd /etc/nixos
git pull
sudo nixos-rebuild switch
```

The flake pins all inputs via `flake.lock`; run `nix flake update` and commit
the result to roll the pins forward.
