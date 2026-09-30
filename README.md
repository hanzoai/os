# os

The estate's operating system, as an expression.

Two outputs from one flake: the images an agent's code runs in, and the
configuration a machine is. Both are derived from inputs pinned by hash, so the
same expression gives the same bytes — today, and in a year.

```sh
nix build .#exec        # the sandbox image
nix build .#exec --rebuild   # and prove it is the same bytes
```

## Why

The sandbox image was a 2GB Debian blob pinned by digest. On 2026-09-09 all four
of those digests — exec, dev, desktop, admin — answered 404 while their tags
still resolved: the manifests had moved under the tags. Every sandbox stopped
starting, and nothing had changed on our side.

A tag is a name someone else can move. A hash is not.

```
current   2.0 GB   22 layers   Debian, 62 build steps, digest moved under us
this      222 MB   nix-built   rebuild → byte-identical, checked by nix --rebuild
```

Nine times smaller is the side effect. The point is the second line: `--rebuild`
re-derives the image and verifies the output matches. That is not a promise in a
README, it is a check that fails loudly.

## Sandboxes

`sandbox/default.nix`. Four classes, the same four the sandbox surface asks for
by name:

| class | toolchain |
|---|---|
| `exec` | python, node — a code-interpreter call |
| `dev` | + go, rust, gcc, make — a workspace bound to a project |
| `desktop` | + xvfb — one with a screen |
| `admin` | + kubectl, helm |

Every class keeps the shape the runtime already hands the pod: `tini` as pid 1,
user `sandbox`, workdir `/work`. That contract is the runtime's, not ours.

`created` is pinned to the epoch. dockerTools does that by default; it is named
here because a timestamp is the one field that would make two identical builds
produce two different digests.

## Nodes

`node/grid.nix` is [grid](https://github.com/hanzoai/grid) as a NixOS module —
what a machine runs to be part of the cluster.

```nix
hanzo.grid = {
  enable = true;
  role = "node";
  serverAddr = "https://localhost:6443";
  tokenFile = "/var/lib/secrets/grid-token";
  nodeIp = "127.0.0.1";
  flannelIface = "eno1";
  labels."hanzo.ai/arch" = "amd64";
};
```

What this replaces is a `config.yaml` and a unit edited by hand on each machine,
read only at start and reconciled by nothing — so a rebuilt node lost every line,
and the lines were load-bearing. Each option carries why it exists: flannel does
not follow `nodeIp`; k3s's stock `eviction-hard` REPLACES the kubelet's default
set rather than extending it; the image-GC threshold is a percentage of the whole
disk, which a busy node crosses and cannot get back under.

And `nixos-rebuild --rollback` undoes a bad one atomically, which is the part that
matters at 3am.

## Where this sits

| | |
|---|---|
| [grid](https://github.com/hanzoai/grid) | the substrate a machine joins the cluster with |
| [visor](https://github.com/hanzoai/visor) | the sandbox untrusted code runs in |
| **os** | what both are built from |
