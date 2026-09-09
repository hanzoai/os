# The images an agent's code runs in.
#
# One expression, four classes, and the class decides the toolchain — the same
# four the sandbox surface asks for by name (exec, dev, desktop, admin). What
# makes this worth doing is not the size: it is that `exec` a year from now is
# the same bytes as `exec` today, because the inputs are a hash and not a tag
# that something can move underneath us. All four digests the cloud pinned did
# exactly that, and every sandbox stopped starting.
{ pkgs }:

let
  inherit (pkgs) lib dockerTools buildEnv;

  # Present in every class. An agent needs a shell, the network, and the tools
  # it reaches for without asking.
  base = with pkgs; [
    bashInteractive coreutils findutils gnugrep gnused gawk diffutils patch
    gnutar gzip xz zstd
    curl wget cacert
    git openssh
    jq ripgrep fd tree less procps
    tini
  ];

  toolchains = {
    exec = with pkgs; [ python3 nodejs_22 ];
    dev = with pkgs; [ python3 nodejs_22 go gcc gnumake pkg-config rustc cargo ];
    desktop = with pkgs; [ python3 nodejs_22 go gcc gnumake xorg.xvfb ];
    admin = with pkgs; [ python3 nodejs_22 go kubectl kubernetes-helm ];
  };

  # Every class runs as this account, in this directory, under tini — the shape
  # the runtime already hands the pod. It is not ours to change here.
  user = "sandbox";
  uid = "1000";
  home = "/home/${user}";
  work = "/work";

  passwd = pkgs.writeTextDir "etc/passwd" ''
    root:x:0:0:root:/root:/bin/sh
    ${user}:x:${uid}:${uid}:sandbox:${home}:${pkgs.bashInteractive}/bin/bash
    nobody:x:65534:65534:nobody:/:/bin/false
  '';
  group = pkgs.writeTextDir "etc/group" ''
    root:x:0:
    ${user}:x:${uid}:
    nobody:x:65534:
  '';

  image = class: packages:
    dockerTools.buildLayeredImage {
      name = "sandbox";
      tag = class;
      # Reproducible by construction: no timestamp, so the same inputs give the
      # same digest. dockerTools defaults this to the epoch; naming it here is
      # the point of the exercise.
      created = "1970-01-01T00:00:01Z";
      maxLayers = 64;

      contents = buildEnv {
        name = "sandbox-${class}";
        paths = base ++ packages ++ [ passwd group ];
        pathsToLink = [ "/bin" "/lib" "/share" "/etc" "/include" ];
      };

      extraCommands = ''
        mkdir -p work tmp ${lib.removePrefix "/" home}
        chmod 1777 tmp
      '';

      config = {
        Entrypoint = [ "${pkgs.tini}/bin/tini" "--" ];
        Cmd = [ "sleep" "infinity" ];
        WorkingDir = work;
        User = user;
        Env = [
          "PATH=${home}/.local/bin:/bin"
          "HOME=${home}"
          "LANG=C.UTF-8"
          "LC_ALL=C.UTF-8"
          "TZ=UTC"
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "PIP_DISABLE_PIP_VERSION_CHECK=1"
          "NPM_CONFIG_FUND=false"
        ];
      };
    };
in
lib.mapAttrs (class: packages: image class packages) toolchains
