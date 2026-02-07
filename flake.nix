
{
  description = "Deployment script";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.writeShellApplication {
          name = "redeploy.sh";
          runtimeInputs = [
            pkgs.nixos-rebuild
            pkgs.nix-diff
            pkgs.nvd
            pkgs.openssh
          ];
          text = builtins.readFile ./redeploy.sh;
        };
    });
}
