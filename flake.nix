{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    perSystem = { self', pkgs, ... }:
      let
        pkgsWin = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.mingwW64;
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
        make_libcsl_godot = { debug ? false, windows ? false }: (if windows then pkgsWin else pkgs).rustPlatform.buildRustPackage {
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
            # link gdextension
            ln -s ${self'.packages."libcsl_godot${if debug then "-debug" else ""}"}/lib/libcsl_godot.so bin/libcsl_godot.linux.template_${if debug then "debug" else "release"}.x86_64.so

            # link export template
            export HOME=$(mktemp -d)
            TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.2.stable"
            mkdir -p $TEMPLATE_DIR
            ln -s ${self'.packages."godot-export-template${if debug then "-debug" else ""}"}/bin/godot.linuxbsd.template_${if debug then "debug" else "release"}.x86_64 $TEMPLATE_DIR/linux_${if debug then "debug" else "release"}.x86_64

            # build
            mkdir -p out
            ${self'.packages.godot}/bin/godot4 --headless --export-${if debug then "debug" else "release"} "Linux/X11" out/csl_demo
          '';
          installPhase = ''
            [ ! -f out/csl_demo ] && echo "out/csl_demo not built, failing..." && false
            mkdir -p $out/bin
            cp out/* $out/bin/
          '';
          dontFixup = true;
          dontStrip = true;
        };
      in
      {
        packages = rec {
          default = libcsl_godot;
          godot = pkgs.godot_4;
          godot-bin = pkgs.callPackage (import ./godot-bin.nix) { };
          libcsl_godot = make_libcsl_godot { };
          libcsl_godot-win = make_libcsl_godot { windows = true; };
          libcsl_godot-debug = make_libcsl_godot { debug = true; };
          libcsl_godot-win-debug = make_libcsl_godot { windows = true; debug = true; };
          godot-export-template = make_godot-export-template { };
          godot-export-template-debug = make_godot-export-template { debug = true; };
          csl_demo = make_csl_demo { };
          csl_demo-debug = make_csl_demo { debug = true; };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
