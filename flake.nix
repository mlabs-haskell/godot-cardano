{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, fenix, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    perSystem = { pkgs, ... }: {
      packages = rec {
        default = libcsl_godot;
        godot_4 = pkgs.godot_4;
        libcsl_godot = pkgs.rustPlatform.buildRustPackage {
          name = "libcsl_godot";
          src = ./libcsl_godot;
          cargoLock = {
            lockFile = ./libcsl_godot/Cargo.lock;
            allowBuiltinFetchGit = true;
          };
        };
        libcsl_godot-debug = pkgs.rustPlatform.buildRustPackage {
          name = "libcsl_godot";
          src = ./libcsl_godot;
          cargoLock = {
            lockFile = ./libcsl_godot/Cargo.lock;
            allowBuiltinFetchGit = true;
          };
          buildType = "debug";
        };
      };
    };
    systems = [ "x86_64-linux" ];
  };
}
