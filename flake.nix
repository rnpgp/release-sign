{
  description = "Release signing tool for GitHub projects";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell/main";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , devshell
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      overlays = map (x: x.overlays.default) [
        devshell
      ];
      pkgs = import nixpkgs { inherit system overlays; };
      thePackage = pkgs.callPackage ./default.nix { };
    in
    rec {
      defaultApp = flake-utils.lib.mkApp {
        drv = defaultPackage;
      };
      defaultPackage = thePackage;

      # nix develop
      devShell = pkgs.devshell.mkShell {
        env = [
        ];
        commands = [
        ];
        packages = with pkgs; [
          bash
          curl
          gnutar
          thePackage
          unzip
        ];
      };
    });
}
