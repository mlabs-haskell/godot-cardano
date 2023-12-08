{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, fenix, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    perSystem = { self', pkgs, ... }:
      let
        make_libcsl_godot = args: pkgs.rustPlatform.buildRustPackage ({
          name = "libcsl_godot";
          src = ./libcsl_godot;
          cargoLock = {
            lockFile = ./libcsl_godot/Cargo.lock;
            allowBuiltinFetchGit = true;
          };
        } // args);
        make_csl_demo = { debug ? false }: pkgs.stdenv.mkDerivation {
          name = "csl_demo";
          src = ./csl_demo;
          buildPhase = ''
            ln -s ${if debug then self'.packages.libcsl_godot-debug else self'.packages.libcsl_godot}/lib/libcsl_godot.so bin/libcsl_godot.linux.template_${if debug then "debug" else "release"}.x86_64.so
            export HOME=$(mktemp -d)
            mkdir out
            ${self'.packages.godot_4}/bin/godot4 --headless --export-${if debug then "debug" else "release"} Linux/X11 ./project.godot out
            # TODO: above command fails but exits with code 0. need to check output exists
          '';
          installPhase = ''
            mkdir -p $out
            touch $out/TODO
          '';
        };
      in
      {
        packages = rec {
          default = libcsl_godot;
          godot_4 = pkgs.godot_4;
          libcsl_godot = make_libcsl_godot { };
          libcsl_godot-debug = make_libcsl_godot { buildType = "debug"; };
          csl_demo = make_csl_demo { };
          csl_demo-debug = make_csl_demo { debug = true; };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
