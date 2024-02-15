{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    gut = { url = "github:bitwes/gut/v9.2.0"; flake = false; };
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    perSystem = { self', pkgs, ... }:
      let
        pkgsCrossWin = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.mingwW64;
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
        make_libcsl_godot = { debug ? false, windows ? false }: (if windows then pkgsCrossWin else pkgs).rustPlatform.buildRustPackage {
          name = "libcsl_godot";
          src = ./libcsl_godot;
          buildType = if debug then "debug" else "release";
          cargoLock = {
            lockFile = ./libcsl_godot/Cargo.lock;
            allowBuiltinFetchGit = true;
          };
        };
        make_addon = {}: pkgs.runCommand "godot-cardano"
          {
            dontFixup = true;
            dontStrip = true;
          } ''
          OUT_DIR="$out/addons/@mlabs-haskell/godot-cardano"
          mkdir -p "$OUT_DIR/bin"
          cp -r ${./addons}/@mlabs-haskell/godot-cardano/* $OUT_DIR/ --no-preserve=mode,ownership
          cp "${make_libcsl_godot { windows = false; debug = true;} }/lib/libcsl_godot.so" "$OUT_DIR/bin/libcsl_godot.linux.template_debug.x86_64.so"
          cp "${make_libcsl_godot { windows = false; debug = false;} }/lib/libcsl_godot.so" "$OUT_DIR/bin/libcsl_godot.linux.template_release.x86_64.so"
          cp "${make_libcsl_godot { windows = true; debug = true;} }/bin/csl_godot.dll" "$OUT_DIR/bin/libcsl_godot.windows.template_debug.x86_64.dll"
          cp "${make_libcsl_godot { windows = true; debug = false;} }/bin/csl_godot.dll" "$OUT_DIR/bin/libcsl_godot.windows.template_release.x86_64.dll"
        '';
        make_gd_project = { name, src, debug ? false, windows ? false }: (if windows then pkgsCrossWin else pkgs).stdenv.mkDerivation {
          inherit name src;
          SYSTEM = if windows then "windows" else "linux";
          VARIANT = if debug then "debug" else "release";
          configurePhase = ''
            # link addon
            rm -rf ./addons/@mlabs-haskell/godot-cardano
            mkdir -p ./addons/@mlabs-haskell
            ln -s ${make_addon {}}/addons/@mlabs-haskell/godot-cardano ./addons/@mlabs-haskell/godot-cardano
          '';
          buildPhase = ''
            # link export templates
            mkdir -p .home
            export HOME=$(pwd)/.home
            TEMPLATES_PACKAGE="${make_godot-export-templates-bin {}}"
            TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.2.stable"
            mkdir -p $(dirname $TEMPLATE_DIR)
            ln -s $TEMPLATES_PACKAGE $TEMPLATE_DIR

            mkdir -p out
            ${self'.packages.godot}/bin/godot4 \
              --headless \
              --export-$VARIANT \
              "${if windows then "Windows Desktop" else "Linux/X11"}" \
              ./out/${name}${if windows then ".exe" else ""} \
              ./project.godot
          '';
          installPhase = ''
            [ ! -f out/${name}${if windows then ".exe" else ""} ] && echo "out/${name}${if windows then ".exe" else ""} not built, failing..." && false
            mkdir -p $out/bin
            cp out/* $out/bin/
          '';
          dontFixup = true;
          dontStrip = true;
        };
        make_demo = { name ? "demo", src ? ./demo, ... }@args:
          make_gd_project (args // { inherit name src; });
        run_gut_test = { name ? "godot-cardano-test", src ? ./test }: pkgs.stdenv.mkDerivation {
          inherit name src;
          configurePhase = ''
            rm -rf ./addons/gut
            mkdir -p ./addons
            ln -s ${inputs.gut}/addons/gut ./addons/gut

            rm -rf ./addons/@mlabs-haskell/godot-cardano
            mkdir -p ./addons/@mlabs-haskell
            ln -s ${make_addon {}}/addons/@mlabs-haskell/godot-cardano ./addons/@mlabs-haskell/godot-cardano
          '';
          buildPhase = ''
            mkdir -p .home
            export HOME=$(pwd)/.home
            echo "Reimporting resources..."
            timeout 10s ${self'.packages.godot}/bin/godot4 --headless --editor || true
            echo "Reimporting resources done."
            ${self'.packages.godot}/bin/godot4 --headless --debug --script res://addons/gut/gut_cmdln.gd
          '';
          installPhase = "touch $out";
          dontFixup = true;
        };
      in
      {
        checks = {
          test = run_gut_test { };
        };
        packages = rec {
          default = godot-cardano;
          steam-run = pkgs.steamPackages.steam-fhsenv-without-steam.run;
          godot = pkgs.godot_4;
          godot-bin = pkgs.callPackage (import ./godot-bin.nix) { };
          libcsl_godot = make_libcsl_godot { };
          libcsl_godot-debug = make_libcsl_godot { debug = true; };
          libcsl_godot-windows = make_libcsl_godot { windows = true; };
          libcsl_godot-windows-debug = make_libcsl_godot { windows = true; debug = true; };
          godot-export-template = make_godot-export-template { };
          godot-export-template-debug = make_godot-export-template { debug = true; };
          godot-export-templates-bin = make_godot-export-templates-bin { };
          godot-cardano = make_addon { };
          demo = make_demo { };
          demo-debug = make_demo { debug = true; };
          demo-windows = make_demo { windows = true; };
          demo-windows-debug = make_demo { windows = true; debug = true; };
          test = run_gut_test { };
        };
        devShells = {
          default = pkgs.mkShell {
            buildInputs = [
              self'.packages.godot
              self'.packages.steam-run
              pkgs.cargo
              pkgs.rustc
            ];
            shellHook = ''
              set -e
              test -f demo/project.godot

              mkdir -p demo/out

              # link gdextension
              rm -f addons/@mlabs-haskell/godot-cardano/bin/libcsl_godot.*.template_*.*
              ln -s ../../../../libcsl_godot/target/debug/libcsl_godot.so 'addons/@mlabs-haskell/godot-cardano/bin/libcsl_godot.linux.template_debug.x86_64.so'

              link-addon () {
                rm -rf ./addons/@mlabs-haskell/godot-cardano
                ln -s ../../../addons/@mlabs-haskell/godot-cardano ./addons/@mlabs-haskell/godot-cardano
              }
              (cd demo &&  (${self'.packages.demo.configurePhase}) && link-addon)
              (cd test && (${self'.packages.test.configurePhase}) && link-addon)

              set +e
            '';
          };
          cross-windows = pkgs.mkShell {
            buildInputs = [
              self'.packages.godot
              pkgsCrossWin.rustPlatform.rust.cargo
              pkgsCrossWin.rustPlatform.rust.rustc
            ];
            shellHook = self'.devShells.default.shellHook;
          };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
