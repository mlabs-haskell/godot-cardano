{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, fenix, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    perSystem = { self', pkgs, ... }:
      let
        make_godot-export-template = { debug ? false }:
          (self'.packages.godot.override (_: {
            withTarget = "template_${if debug then "debug" else "release"}";
          })
          ).overrideAttrs {
            pname = "godot-export-templates";
            outputs = [ "out" ];
            installPhase = ''
              mkdir -p $out/bin
              cp bin/* $out/bin/
            '';
          };
        make_libcsl_godot = { debug ? false }: pkgs.rustPlatform.buildRustPackage {
          name = "libcsl_godot";
          src = ./libcsl_godot;
          buildType = if debug then "debug" else "release";
          cargoLock = {
            lockFile = ./libcsl_godot/Cargo.lock;
            allowBuiltinFetchGit = true;
          };
        };
        make_csl_demo = { debug ? false }: pkgs.stdenv.mkDerivation {
          name = "csl_demo";
          src = ./csl_demo;
          buildPhase = ''
            ln -s ${if debug then self'.packages.libcsl_godot-debug else self'.packages.libcsl_godot}/lib/libcsl_godot.so bin/libcsl_godot.linux.template_${if debug then "debug" else "release"}.x86_64.so
            export HOME=$(mktemp -d)
            mkdir out
            ${self'.packages.godot}/bin/godot4 --headless --export-${if debug then "debug" else "release"} Linux/X11 ./project.godot out
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
          godot = pkgs.godot_4;
          libcsl_godot = make_libcsl_godot { };
          libcsl_godot-debug = make_libcsl_godot { debug = true; };
          godot-export-template = make_godot-export-template { };
          godot-export-template-debug = make_godot-export-template { debug = true; };
          csl_demo = make_csl_demo { };
          csl_demo-debug = make_csl_demo { debug = true; };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
