# grid, as a NixOS module.
#
# What this replaces is a config.yaml and a unit file edited by hand on each
# machine, read only at start, reconciled by nothing — so a rebuilt node lost
# every line and the lines were load-bearing. Here the node IS the expression,
# and `nixos-rebuild --rollback` undoes a bad one atomically instead of leaving
# someone to remember what it used to say.
{ config, lib, pkgs, ... }:

let
  cfg = config.hanzo.grid;
in
{
  options.hanzo.grid = {
    enable = lib.mkEnableOption "grid — this machine is part of the cluster";

    role = lib.mkOption {
      type = lib.types.enum [ "server" "node" ];
      default = "node";
      description = "server runs the control plane; node joins one.";
    };

    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "https://<server>:6443. Empty on the server itself.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the join token, read at start and never in the store — a store
        path is world-readable, which is the whole reason this is a file and not
        a string.
      '';
    };

    nodeIp = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The address this node is reached at. Name it when the machine has more
        than one and the right one is not the default route's: on the cable
        rather than the wifi, for instance.
      '';
    };

    flannelIface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        flannel does NOT follow nodeIp. Given no interface it binds the one
        holding the default route, so a node addressed on a second link ends up
        with its data plane crossing the first — half migrated, which is worse
        than either end alone.
      '';
    };

    labels = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { "hanzo.ai/arch" = "amd64"; };
    };

    taints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "hanzo.ai/no-ci=true:NoSchedule" ];
      description = ''
        A NoSchedule taint excludes EVERYTHING without a matching toleration, so
        it admits by exception rather than refusing by exception. On a cluster
        with one node of an architecture, that is the whole fleet.
      '';
    };

    imageGc = {
      high = lib.mkOption {
        type = lib.types.int;
        default = 92;
        description = ''
          A PERCENTAGE of the whole filesystem. The kubelet's default 85 sits at
          819G of a 964G disk — a line a node with a hundred images in use
          crosses and cannot get back under, after which it runs GC every few
          minutes, fails, and evicts LIVE images instead. The eviction floor
          below is what actually protects the node, and it is absolute.
        '';
      };
      low = lib.mkOption { type = lib.types.int; default = 85; };
    };
  };

  config = lib.mkIf cfg.enable {
    services.k3s = {
      enable = true;
      role = cfg.role;
      tokenFile = cfg.tokenFile;
      serverAddr = cfg.serverAddr;

      extraFlags =
        (lib.optionals (cfg.nodeIp != "") [ "--node-ip=${cfg.nodeIp}" ])
        ++ (lib.optionals (cfg.flannelIface != "") [ "--flannel-iface=${cfg.flannelIface}" ])
        ++ (lib.mapAttrsToList (k: v: "--node-label=${k}=${v}") cfg.labels)
        ++ (map (t: "--node-taint=${t}") cfg.taints)
        ++ [
          # k3s's stock eviction-hard REPLACES the kubelet's default threshold
          # set rather than extending it, so a node left on it has no
          # memory.available signal at all and the eviction manager can never
          # fire on memory pressure. With swap and failSwapOn=false the machine
          # swaps until it stops answering.
          "--kubelet-arg=eviction-hard=memory.available<4Gi,nodefs.available<20Gi,nodefs.inodesFree<5%,imagefs.available<20Gi"
          "--kubelet-arg=eviction-soft=memory.available<8Gi,nodefs.available<40Gi,imagefs.available<40Gi"
          "--kubelet-arg=eviction-soft-grace-period=memory.available=1m30s,nodefs.available=2m,imagefs.available=2m"
          "--kubelet-arg=image-gc-high-threshold=${toString cfg.imageGc.high}"
          "--kubelet-arg=image-gc-low-threshold=${toString cfg.imageGc.low}"
          "--kubelet-arg=max-pods=250"
        ];
    };

    # br_netfilter and overlay before start, every boot. The unit does this by
    # hand today and a machine that reboots without them comes back with a
    # network that half works.
    boot.kernelModules = [ "br_netfilter" "overlay" ];

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.role == "server") [ 6443 ];
  };
}
