{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    # TODO: use up-to-date nixpkgs and godot and godot-cpp, fix build problems
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    godot-cpp.url = "github:godotengine/godot-cpp/godot-4.0.2-stable";
    godot-cpp.flake = false;
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, ... }:
    let
      godot-cpp = { stdenv, scons }: stdenv.mkDerivation {
        name = "godot-cpp";
        src = inputs.godot-cpp;
        buildInputs = [ scons ];
        # TODO: use multiple outputs
        outputs = [ "lib" ];
        buildPhase = ''
          scons TARGET=linux64
        '';
        installPhase = ''
          mkdir -p $out/lib
          cp bin/* $out/lib
        '';
      };
      gdExtension = { name, src, stdenv, scons }: stdenv.mkDerivation {
        inherit name src;
        buildInputs = [ scons ];
        preConfigure = ''
          # TODO: use pre-built godot-cpp
          cp -r ${inputs.godot-cpp} godot-cpp
          chmod -R u+w godot-cpp
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp bin/* $out/bin
        '';
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      perSystem = { self', pkgs, ... }: {
        packages = {
          godot_4 = pkgs.godot_4;
          godot-cpp = pkgs.callPackage godot-cpp { };
          default = self.packages.godot-crypto;
          godot-crypto = pkgs.callPackage gdExtension {
            src = ./gdextension;
            name = "godot-crypto";
          };
        };
      };
      systems = [ "x86_64-linux" ];
    };
}
