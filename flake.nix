{
  description = "Release signing tool for GitHub projects";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        thePackage = pkgs.callPackage ./default.nix { };
      in
      rec {
        defaultApp = flake-utils.lib.mkApp {
          drv = defaultPackage;
        };
        defaultPackage = thePackage;
        devShell = pkgs.mkShell {
          buildInputs = [
            thePackage
          ];
        };
      });
}
