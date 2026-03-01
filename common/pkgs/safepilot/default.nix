{ pkgs, lib, copilotSupport ? true, geminiSupport ? false, gitSupport ? true }:

let
  baseTools = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    which
    curl
    wget
    ripgrep
    fd
    jq
    diffutils
    patch
    file
    tree
    gnutar
    gzip
    unzip
    python3
    uv
    gnumake
    vim
    nix
    devenv
  ];

  tools = baseTools
    ++ lib.optionals gitSupport     (with pkgs; [ git gh ])
    ++ lib.optionals copilotSupport (with pkgs; [ github-copilot-cli ])
    ++ lib.optionals geminiSupport  (with pkgs; [ gemini-cli ]);

  nixConf = pkgs.writeTextFile {
    name = "nix-conf";
    destination = "/etc/nix/nix.conf";
    text = ''
      sandbox = false
      filter-syscalls = false
      experimental-features = nix-command flakes
    '';
  };

  # All paths baked into the image root, shared between copyToRoot and
  # closureInfo so they stay in sync.
  containerPaths = tools ++ [ pkgs.dockerTools.fakeNss pkgs.cacert nixConf ];

  # Loaded into the nix DB on first container start so nix treats baked-in
  # store paths as valid and won't attempt to re-substitute them.
  storeRegistration = pkgs.closureInfo { rootPaths = containerPaths; };

  entrypoint = pkgs.writeShellScript "safepilot-entrypoint" ''
    if [[ ! -f /nix/var/nix/db/db.sqlite ]]; then
      nix-store --load-db < /nix/registration
    fi
    exec "$@"
  '';

  image = pkgs.dockerTools.buildImage {
    name = "safepilot";
    tag = "latest";

    copyToRoot = pkgs.buildEnv {
      name = "safepilot-root";
      paths = containerPaths;
    };

    extraCommands = ''
      mkdir -p home/user
      chmod 1777 home/user
      mkdir -p workspace
      mkdir -p tmp
      chmod 1777 tmp

      mkdir -p nix/store
      chmod 1777 nix/store

      mkdir -p nix/var/nix/db
      mkdir -p nix/var/nix/profiles
      mkdir -p nix/var/nix/gcroots/profiles
      mkdir -p nix/var/nix/temproots
      mkdir -p nix/var/nix/userpool
      mkdir -p nix/var/log/nix/drvs
      chmod -R 1777 nix/var

      cp ${storeRegistration}/registration nix/registration
    '';

    config = {
      WorkingDir = "/workspace";
      Entrypoint = [ "${entrypoint}" ];
      Cmd = [ "${pkgs.bashInteractive}/bin/bash" ];
      Env = [
        "PATH=${lib.makeBinPath tools}"
        "HOME=/home/user"
        "USER=user"
        "TERM=xterm-256color"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };

  loadScript = pkgs.writeShellScriptBin "safepilot-load" ''
    set -euo pipefail
    echo "Loading safepilot image into podman..."
    podman load < ${image}
    echo "Done. Run 'safepilot' to start a session."
  '';

  # Usage:
  #   safepilot
  #   safepilot -v .:.:rw
  #   safepilot -v /etc/nixos:nixos:r
  #   safepilot -v .:.:rw -v ~/docs:docs:r
  #
  # Mount spec: host_path:dest:mode
  #   host_path  path on host; "." expands to $PWD, "~" is expanded
  #   dest       name under /workspace; "." means /workspace itself
  #   mode       r (read-only) or rw (read-write)
  launcher = pkgs.writeShellScriptBin "safepilot" ''
    set -euo pipefail

    if ! podman image exists localhost/safepilot:latest 2>/dev/null; then
      echo "safepilot image not found. Run 'safepilot-load' first." >&2
      exit 1
    fi

    # Temp passwd/group so tools resolve username correctly inside container
    passwd_tmp=$(mktemp)
    group_tmp=$(mktemp)
    trap 'rm -f "$passwd_tmp" "$group_tmp"' EXIT
    printf 'root:x:0:0:root:/root:/bin/sh\n' > "$passwd_tmp"
    printf 'user:x:%s:%s::/home/user:/bin/bash\n' "$(id -u)" "$(id -g)" >> "$passwd_tmp"
    printf 'nobody:x:65534:65534:Nobody:/:/bin/sh\n' >> "$passwd_tmp"
    printf 'root:x:0:\n' > "$group_tmp"
    printf 'user:x:%s:\n' "$(id -g)" >> "$group_tmp"
    printf 'nobody:x:65534:\n' >> "$group_tmp"

    mounts=()
    env_args=()

    mounts+=("-v" "$passwd_tmp:/etc/passwd:ro")
    mounts+=("-v" "$group_tmp:/etc/group:ro")

    # Parse -v host:dest:mode arguments
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -v)  shift; spec="$1" ;;
        -v*) spec="''${1#-v}" ;;
        *)
          echo "Error: unknown argument '$1'" >&2
          echo "Usage: safepilot [-v host:dest:mode ...]" >&2
          echo "  mode: r (read-only) or rw (read-write)" >&2
          echo "  dest: name under /workspace, or '.' for /workspace itself" >&2
          exit 1 ;;
      esac
      shift

      IFS=':' read -r host_path dest mode <<< "$spec"
      if [[ -z "$host_path" || -z "$dest" || -z "$mode" ]]; then
        echo "Error: invalid mount spec '$spec'" >&2
        echo "  Format: -v host_path:dest:mode" >&2
        exit 1
      fi

      [[ "$host_path" == "." ]] && host_path="$PWD"
      host_path="''${host_path/#\~/$HOME}"
      [[ "$dest" == "." ]] && dest_path="/workspace" || dest_path="/workspace/$dest"

      case "$mode" in
        rw) mounts+=("-v" "$host_path:$dest_path:rw") ;;
        r)  mounts+=("-v" "$host_path:$dest_path:ro") ;;
        *)  echo "Error: mode must be 'r' or 'rw', got: '$mode'" >&2; exit 1 ;;
      esac
    done

    # Implicit mounts: only what tools need to function
    ${lib.optionalString geminiSupport ''
    mkdir -p "$HOME/.gemini"
    mounts+=("-v" "$HOME/.gemini:/home/user/.gemini:rw")
    ''}
    ${lib.optionalString copilotSupport ''
    mkdir -p "$HOME/.copilot"
    mounts+=("-v" "$HOME/.copilot:/home/user/.copilot:rw")
    ''}
    ${lib.optionalString gitSupport ''
    [[ -f "$HOME/.gitconfig" ]] && mounts+=("-v" "$HOME/.gitconfig:/home/user/.gitconfig:ro")
    ''}

    ${lib.optionalString gitSupport ''
    git_name=$(${pkgs.git}/bin/git config --global user.name 2>/dev/null || true)
    git_email=$(${pkgs.git}/bin/git config --global user.email 2>/dev/null || true)
    [[ -n "$git_name" ]]  && env_args+=("-e" "GIT_AUTHOR_NAME=$git_name"   "-e" "GIT_COMMITTER_NAME=$git_name")
    [[ -n "$git_email" ]] && env_args+=("-e" "GIT_AUTHOR_EMAIL=$git_email" "-e" "GIT_COMMITTER_EMAIL=$git_email")
    ''}

    env_args+=("-e" "TERM=''${TERM:-xterm-256color}")
    [[ -n "''${COLORTERM:-}" ]] && env_args+=("-e" "COLORTERM=$COLORTERM")

    podman run \
      --rm \
      --interactive \
      --tty \
      --userns=keep-id \
      --workdir /workspace \
      -e HOME=/home/user \
      "''${mounts[@]}" \
      "''${env_args[@]}" \
      localhost/safepilot:latest \
      bash
  '';

in pkgs.symlinkJoin {
  name = "safepilot";
  paths = [ launcher loadScript ];
  meta = {
    description = "Sandboxed AI coding environment via podman";
    mainProgram = "safepilot";
  };
}
