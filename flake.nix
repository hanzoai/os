{
  description = "hanzoai/os — the estate's operating system, as an expression";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      each = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      # The images an agent's code runs in. One expression per class, the same
      # classes the sandbox surface asks for by name.
      packages = each (system: pkgs: import ./sandbox { inherit pkgs; });

      # What a machine runs to be part of the cluster. grid's config.yaml and
      # unit, as a module.
      nixosModules.grid = import ./node/grid.nix;

      devShells = each (system: pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nixfmt-rfc-style pkgs.skopeo ];
        };
      });

      formatter = each (system: pkgs: pkgs.nixfmt-rfc-style);
    };
}
