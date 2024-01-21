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
        make_godot-export-templates-bin = { version ? "4.2.1" }: pkgs.stdenv.mkDerivation {
          name = "godot-export-templates-bin";
          inherit version;
          src = pkgs.fetchurl {
            url = "https://github.com/godotengine/godot/releases/download/${version}-stable/Godot_v${version}-stable_export_templates.tpz";
            sha256 = "sha256-xfFA61eEY6L6FAfzXjfBeqNKS4R7nTDinDhHuV5t2gc=";
          };
          dontUnpack = true;
          installPhase = ''
            ${pkgs.p7zip}/bin/7z x $src
            mv templates $out
          '';
        };
        make_godot-export-template = { debug ? false, windows ? false }:
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
        make_demo = { debug ? false, windows ? false }: pkgs.stdenv.mkDerivation {
          name = "demo";
          src = ./demo;
          buildPhase = ''
            SYSTEM="${if windows then "windows" else "linux"}"
            VARIANT="${if debug then "debug" else "release"}"

            # copy addons directory
            rm ./addons
            cp -r ${./addons} ./addons --no-preserve=mode,ownership

            # link debug gdextension
            ln -s "${make_libcsl_godot { windows = false; debug = true;} }/lib/libcsl_godot.so" "addons/@mlabs-haskell/gd-cardano/bin/libcsl_godot.linux.template_debug.x86_64.so"

            # link gdextension
            GDEXTENSION_PACKAGE="${make_libcsl_godot { inherit debug windows; }}"
            GDEXTENSION="$GDEXTENSION_PACKAGE/${if windows then "bin/csl_godot.dll" else "lib/libcsl_godot.so"}"
            GDEXTENSION_LINK_NAME="addons/@mlabs-haskell/gd-cardano/bin/libcsl_godot.$SYSTEM.template_$VARIANT.x86_64.${if windows then "dll" else "so"}"
            ln -sf $GDEXTENSION $GDEXTENSION_LINK_NAME

            # link export templates
            export HOME=$(mktemp -d)
            TEMPLATES_PACKAGE="${make_godot-export-templates-bin {}}"
            TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.2.stable"
            mkdir -p $(dirname $TEMPLATE_DIR)
            ln -s $TEMPLATES_PACKAGE $TEMPLATE_DIR

            # build
            mkdir -p out
            ${self'.packages.godot}/bin/godot4 \
              --headless \
              --export-$VARIANT \
              "${if windows then "Windows Desktop" else "Linux/X11"}" \
              ./out/demo${if windows then ".exe" else ""} \
              ./project.godot
          '';
          installPhase = ''
            [ ! -f out/demo${if windows then ".exe" else ""} ] && echo "out/demo${if windows then ".exe" else ""} not built, failing..." && false
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
          godot-export-templates-bin = make_godot-export-templates-bin { };
          demo = make_demo { };
          demo-win = make_demo { windows = true; };
          demo-debug = make_demo { debug = true; };
          demo-win-debug = make_demo { windows = true; debug = true; };
        };
        devShells = {
          default = pkgs.mkShell {
            buildInputs = [
              self'.packages.godot
              pkgs.cargo
              pkgs.rustc
            ];
          };
          windows = pkgs.mkShell {
            buildInputs = [
              self'.packages.godot
              pkgsWin.rustPlatform.rust.cargo
              pkgsWin.rustPlatform.rust.rustc
            ];
          };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
