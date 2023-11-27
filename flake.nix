{
  description = "Cardano Integration for Godot game engine";

  inputs = {
    # TODO: use up-to-date nixpkgs and godot and godot-cpp, fix build problems
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    naersk.url = "github:nix-community/naersk/master";
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
        outputs = [ "out" ];
        buildPhase = ''
          scons TARGET=linux64
        '';
        installPhase = ''
          mkdir -p $out/lib
          cp bin/* $out/lib
        '';
      };
      godot-crypto = { stdenv, scons, libcsl }: stdenv.mkDerivation {
        src = ./gdextension;
        name = "godot-crypto";
        LIBPATH = "${libcsl}/lib";
        buildInputs = [ scons libcsl ];
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
      perSystem = { self', pkgs, ... }:
        let naersk-lib = pkgs.callPackage inputs.naersk { }; in
        {
          packages = {
            godot_4 = pkgs.godot_4;
            godot-cpp = pkgs.callPackage godot-cpp { };
            libcsl = naersk-lib.buildPackage {
              src = ./gdextension/libcsl;
              copyLibs = true;
            };
            default = self'.packages.godot-crypto;
            godot-crypto = pkgs.callPackage godot-crypto { inherit (self'.packages) libcsl; };
          };
        };
      systems = [ "x86_64-linux" ];
    };
}
