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
    procps
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
    stdenv.cc.cc.lib
    zlib
    glibcLocales
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
        "LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ]}"
        "HOME=/home/user"
        "USER=user"
        "TERM=xterm-256color"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "LANG=en_US.UTF-8"
        "LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive"
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
  #   safepilot [PODMAN_ARGS...]
  #
  # All arguments are passed through to podman run as-is, with one convenience:
  # relative paths in -v specs are expanded automatically.
  #
  # -v SOURCE:DEST[:OPTIONS]  standard podman volume mount
  #   SOURCE  relative paths are expanded to absolute ($PWD/...)
  #   DEST    relative paths are prefixed with /workspace/
  #           use "." as DEST to mean /workspace itself
  #
  # Examples:
  #   safepilot -v .:/workspace:rw          # mount CWD as /workspace
  #   safepilot -v .:.:rw                   # same, using relative dest
  #   safepilot -v ./src:src:ro             # mount ./src as /workspace/src
  #   safepilot -v ~/docs:/home/user/docs:rw  # absolute dest, no prefix added
  #   safepilot --network=host              # any podman flag works
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

    # Expand relative paths in a -v spec; absolute paths pass through unchanged.
    # SOURCE: relative → $PWD/..., "." → $PWD, "~" prefix → $HOME/...
    # DEST:   relative → /workspace/..., "." → /workspace
    expand_v() {
      local spec="$1"
      local src dest opts
      IFS=':' read -r src dest opts <<< "$spec"

      src="''${src/#\~/$HOME}"
      [[ "$src" == "." ]] && src="$PWD"
      [[ "$src" != /* ]] && src="$PWD/$src"

      if [[ -n "$dest" && "$dest" != /* ]]; then
        [[ "$dest" == "." ]] && dest="/workspace" || dest="/workspace/$dest"
      fi

      echo "$src:$dest''${opts:+:$opts}"
    }

    mounts=()
    env_args=()
    extra_args=()

    mounts+=("-v" "$passwd_tmp:/etc/passwd:ro")
    mounts+=("-v" "$group_tmp:/etc/group:ro")

    # Intercept -v to expand relative paths; pass everything else to podman.
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -v)  shift; mounts+=("-v" "$(expand_v "$1")") ;;
        -v*) mounts+=("-v" "$(expand_v "''${1#-v}")") ;;
        *)   extra_args+=("$1") ;;
      esac
      shift
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
      "''${extra_args[@]}" \
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
