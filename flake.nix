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
    aiken.url = "github:aiken-lang/aiken?tag=v1.0.28-alpha";

    # plutip test
    cardano-nix.url = "github:mlabs-haskell/cardano.nix";
    # TODO: use cardano.nix after kupo and plutip are merged there
    plutip.url = "github:mlabs-haskell/plutip";
    kupo-nixos.url = "github:mlabs-haskell/kupo-nixos/df5aaccfcec63016e3d9e10b70ef8152026d7bc3";
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" ];
    imports = [
      inputs.pre-commit-hooks.flakeModule
      inputs.hercules-ci-effects.flakeModule
      inputs.devshell.flakeModule
      ./nix/godot-cardano.nix
      ./nix/private-testnet.nix
      ./nix/devshell.nix
    ];
    perSystem = { self', inputs', pkgs, config, ... }: {
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
  };
}
