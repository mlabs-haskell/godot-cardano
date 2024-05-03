{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    gut = { url = "github:bitwes/gut/v9.2.0"; flake = false; };
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
    hercules-ci-effects.url = "github:hercules-ci/hercules-ci-effects";
    hercules-ci-effects.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    # plutip test
    cardano-nix.url = "github:mlabs-haskell/cardano.nix";
    # TODO: use cardano.nix after kupo and plutip are merged there
    plutip.url = "github:mlabs-haskell/plutip";
    kupo-nixos.url = "github:mlabs-haskell/kupo-nixos/df5aaccfcec63016e3d9e10b70ef8152026d7bc3";
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.pre-commit-hooks.flakeModule
      inputs.hercules-ci-effects.flakeModule
      inputs.devshell.flakeModule
      ./nix/private-testnet.nix
      ./nix/devshell.nix
    ];
    perSystem = { self', inputs', pkgs, config, ... }:
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
            mkdir -p .home .godot
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
        gut_check_configure = { name ? "godot-cardano-test", src ? ./test }: pkgs.writeShellScriptBin "gut_check_configure" ''
          rm -rf ./addons/gut
          mkdir -p ./addons
          ln -s ${inputs.gut}/addons/gut ./addons/gut
          rm -rf ./addons/@mlabs-haskell/godot-cardano
          mkdir -p ./addons/@mlabs-haskell
          ln -s ${make_addon {}}/addons/@mlabs-haskell/godot-cardano ./addons/@mlabs-haskell/godot-cardano
        '';
        gut_check_build = { name ? "godot-cardano-test", src ? ./test }: pkgs.writeShellScriptBin "gut_check_build" ''
          mkdir -p .home
          HOME="$(pwd)/.home"
          export HOME
          echo "Reimporting resources..."
          timeout 10s ${self'.packages.godot}/bin/godot4 --headless --editor || true
          echo "Reimporting resources done."
          echo
          RESULT=$(${self'.packages.godot}/bin/godot4 --headless --script res://addons/gut/gut_cmdln.gd)
          echo -e "$RESULT"
          [[ "$RESULT" =~ '---- All tests passed! ----' ]] || (echo "Not all tests passed." && exit 1)
        '';
        run_gut_test = { name ? "godot-cardano-test", src ? ./test }: pkgs.writeShellApplication {
          inherit name;
          text = ''
            [ ! -d test ] && echo "Could not find 'test' directory. Please run this script from the repository root." && exit 1
            cd test
            [ ! -f test.gd ] && echo "Could not find 'test.gd'. Please run this script from the repository root." && exit 1
            ${gut_check_configure {inherit name src; }}/bin/gut_check_configure
            ${gut_check_build {inherit name src; }}/bin/gut_check_build
          '';
        };
        setup-dev-env = pkgs.writeShellScriptBin "setup-dev-env" ''
          # private testnet tests
          rm -rf private-testnet
          mkdir -p private-testnet

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
          (cd test && (  ${gut_check_configure {}}/bin/gut_check_configure) && link-addon)

          ${config.pre-commit.installationScript}

          set +e
        '';
      in
      {
        packages = {
          default = self'.packages.godot-cardano;
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
          pre_commit_checks = config.pre-commit.settings.run;
          preview-integration-test = run_gut_test { };
          inherit (inputs'.cardano-nix.packages) cardano-cli;
          inherit setup-dev-env;
        };
        pre-commit.settings = {
          settings = {
            rust.cargoManifestPath = "libcsl_godot/Cargo.toml";
          };

          hooks = {
            rustfmt.enable = true;
            nixpkgs-fmt.enable = true;
            # FIXME: Clippy can be run offline, but dependencies need to be
            # locally available by then.
            # clippy.enable = true;
          };
        };
      };
    systems = [ "x86_64-linux" ];
  };
}
