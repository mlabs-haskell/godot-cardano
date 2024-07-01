{ inputs, lib, ... }: {
  perSystem = { self', config, pkgs, ... }: {
    packages.docs-reference-json = self'.packages.demo.overrideAttrs (old: {
      name = "reference.json";
      configurePhase = old.configurePhase + ''
        # copy godot documentation export scripts
        cp ${inputs.gdscript-docs-maker}/godot-scripts/CollectorGd4.gd .
        cp ${inputs.gdscript-docs-maker}/godot-scripts/ReferenceCollectorCLIGd4.gd .

        # workaround for bug
        # https://github.com/GDQuest/gdscript-docs-maker/pull/97
        sed -i 's/_init(/_initialize(/g' ReferenceCollectorCLIGd4.gd

        # set input path
        sed -i 's/\"res\:\/\/\"/\"res:\/\/addons\/@mlabs-haskell\/godot-cardano\"/g' ReferenceCollectorCLIGd4.gd
        cat ReferenceCollectorCLIGd4.gd

        # work around crash in provider.gd
        # https://github.com/godotengine/godot/issues/81598
        DIR=$(readlink addons/@mlabs-haskell/godot-cardano)
        rm -f addons/@mlabs-haskell/godot-cardano
        cp -r $DIR addons/@mlabs-haskell/godot-cardano
        chmod -R u+wx addons
        sed 's/^signal.*$//' -i addons/@mlabs-haskell/godot-cardano/src/provider_api.gd
      '';
      buildPhase = ''
        echo "Reimporting resources"
        timeout 10s ${self'.packages.godot}/bin/godot4 --headless --editor || true
        echo "Building reference.json"
        timeout 30s ${self'.packages.godot}/bin/godot4 \
            --headless \
            --editor \
            --exit \
            --script ./ReferenceCollectorCLIGd4.gd \
            || true
        if [ ! -f reference.json ]; then
          echo "Failed to build reference.json"
          exit 1
        fi
      '';
      installPhase = ''
        mv ./reference.json $out
        chmod 444 $out
      '';
    });

    packages.gdscript-docs-maker = pkgs.callPackage ./gdscript-docs-maker.nix { src = inputs.gdscript-docs-maker; };

    packages.docs-reference = pkgs.stdenv.mkDerivation {
      name = "godot-cardano-docs-reference";
      src = ../.;
      buildPhase = ''
        # paths are relative to reference.json, so we need to copy it
        cp ${self'.packages.docs-reference-json} ./reference.json

        # build docs
        ${self'.packages.gdscript-docs-maker}/bin/gdscript-docs-maker ./reference.json

        # fix links
        find ./export/*.md -exec sed -i 's/(\.\.\/Node)/(https:\/\/docs.godotengine.org\/en\/4.2\/classes\/class_node.html)/g' {} \;
        find ./export/*.md -exec sed -i 's/(\.\.\/RefCounted)/(https:\/\/docs.godotengine.org\/en\/4.2\/classes\/class_refcounted.html)/g' {} \;
        find ./export/*.md -exec sed -i 's/(\.\.\/Resource)/(https:\/\/docs.godotengine.org\/en\/4.2\/classes\/class_resource.html)/g' {} \;
        find ./export/*.md -exec sed -i 's/\[BigInt\]/[BigInt](BigInt.md)/g' {} \;
        find ./export/*.md -exec sed -i 's/\[Address\]/[Address](Address.md)/g' {} \;
        find ./export/*.md -exec sed -i 's/\[SingleAddressWallet\]/[SingleAddressWallet](SingleAddressWallet.md)/g' {} \;
        find ./export/*.md -exec sed -i 's/\[\([a-zA-Z0-9]*\)\(_\|\)\.\([_a-zA-Z0-9]*\)\]/[\1.\3](\1.md#\3)/g' {} \;
      '';
      installPhase = ''
        mkdir -p $out
        cp -r export/* $out/
      '';
    };

    packages.mkdocs = pkgs.runCommandNoCC "mkdocs"
      {
        buildInputs = [
          pkgs.mkdocs
          pkgs.python311Packages.mkdocs-material
        ];
      } ''
      mkdir -p $out/bin

      cat <<MKDOCS > $out/bin/mkdocs
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      export PYTHONPATH=$PYTHONPATH
      exec ${pkgs.mkdocs}/bin/mkdocs "\$@"
      MKDOCS

      chmod +x $out/bin/mkdocs
    '';

    packages.docs = pkgs.stdenv.mkDerivation {
      name = "godot-cardano-docs";
      src = ../.;

      nativeBuildInputs = [ config.packages.mkdocs ];

      configurePhase =
        let
          files = builtins.attrNames (builtins.readDir self'.packages.docs-reference);
          txt = lib.concatStringsSep "\n" (map (x: "    - ${lib.head (lib.splitString "." x)}: reference/${x}") files);
          yml = lib.replaceStrings [ "#REFERENCE" ] [ txt ] (builtins.readFile ./mkdocs.yml);
        in
        ''
          cp ${../README.md} docs/index.md
          sed -e 's/(\.\/docs\/M1_PoA-Research-Report\.pdf)/(.\/M1_PoA-Research-Report.pdf)/g' -i docs/index.md
          ln -s ${../.}/screenshots docs/
          ln -s ${builtins.toFile "mkdocs.yml" yml} mkdocs.yml
          ln -s ${self'.packages.docs-reference} docs/reference
        '';

      buildPhase = ''
        cat mkdocs.yml
        mkdocs build -f mkdocs.yml -d site
      '';

      installPhase = ''
        mv site $out
        rm $out/default.nix $out/mkdocs.yml
      '';

      passthru.serve = config.packages.docs-serve;
    };

    packages.docs-serve = pkgs.writeShellScriptBin "docs-serve" ''
      cd $(mktemp -d)
      mkdir docs
      ln -s ${./.}/* ./docs/
      ${self'.packages.docs.configurePhase}
      ${config.packages.mkdocs}/bin/mkdocs serve
    '';

    devshells.default = {
      commands = [
        {
          category = "documentation";
          name = "docs-serve";
          help = "serve documentation web page";
          command = "nix run .#docs-serve";
        }
        {
          category = "documentation";
          name = "docs-build";
          help = "build documentation";
          command = "nix build .#docs";
        }
      ];
      packages = [
        config.packages.mkdocs
      ];
    };

    hercules-ci.github-pages.settings.contents = self'.packages.docs;
  };

  hercules-ci.github-pages.branch = "main";
}
