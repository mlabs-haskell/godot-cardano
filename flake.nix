{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    naersk.url = "github:nix-community/naersk/master";
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    perSystem = { pkgs, ... }:
      let naersk-lib = pkgs.callPackage inputs.naersk { };
      in
      {
        packages = rec {
          default = godot_4;
          godot_4 = pkgs.godot_4;
          libcsl_godot = naersk-lib.buildPackage {
            src = ./libcsl_godot;
            copyLibs = true;
          };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
