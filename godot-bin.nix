{ stdenv
, lib
, autoPatchelfHook
, makeWrapper
, fetchurl
, unzip
, alsaLib
, dbus
, fontconfig
, udev
, vulkan-loader
, libpulseaudio
, libGL
, libXcursor
, libXinerama
, libxkbcommon
, libXrandr
, libXrender
, libX11
, libXext
, libXi
}:
let
  qualifier = "stable";
in
stdenv.mkDerivation rec {
  pname = "godot-bin";
  version = "4.2.1";
  src = fetchurl {
    url = "https://github.com/godotengine/godot/releases/download/${version}-${qualifier}/Godot_v${version}-${qualifier}_linux.x86_64.zip";
    sha256 = "sha256-hjEannW3RF60IVMS5gTfH2nHLUZBrz5nBJ4wNWrjdmA=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper unzip ];

  buildInputs = [
    alsaLib
    dbus
    dbus.lib
    fontconfig
    udev
    vulkan-loader
    libpulseaudio
    libGL
    libX11
    libXcursor
    libXinerama
    libxkbcommon
    libXrandr
    libXrender
    libXi
    libXext
  ];

  libraries = lib.makeLibraryPath buildInputs;

  unpackCmd = "unzip $curSrc -d source";
  installPhase = ''
    mkdir -p $out/bin
    install -m 0755 Godot_v${version}-${qualifier}_linux.x86_64 $out/bin/godot
  '';

  postFixup = ''
    wrapProgram $out/bin/godot \
      --set LD_LIBRARY_PATH ${libraries}
  '';
}
