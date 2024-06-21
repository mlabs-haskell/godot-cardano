{ lib, python3, fetchPypi, src, bash }:
python3.pkgs.buildPythonApplication rec {
  pname = "gdscript-docs-maker";
  version = "0.1.0";
  inherit src;
  postInstall = ''
    mkdir -p $out/bin
    cat <<-EOF > $out/bin/gdscript-docs-maker
    #!${bash}/bin/bash
    export PYTHONPATH=$PYTHONPATH:$out/lib/python*/site-packages
    ${python3}/bin/python -m gdscript_docs_maker \$@
    EOF
    chmod a+x $out/bin/gdscript-docs-maker
  '';
}
