{
  perSystem = { self', config, pkgs, ... }: {
    packages.mkdocs = pkgs.runCommand "my-mkdocs"
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
      src = ../.;
      name = "godot-cardano-docs";

      nativeBuildInputs = [ config.packages.docs ];

      configurePhase = ''
        ln -s ${../README.md} docs/index.md
        ln -s ${../.}/screenshots docs/
        ln -s ${./mkdocs.yml} mkdocs.yml
      '';

      buildPhase = ''
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

  hercules-ci.github-pages.branch = "marton/docs";
}
