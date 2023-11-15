## WIP: Godot engine crypto integration.

Currently:
- build Godot and an example GDExtension on linux
- look into building Godot C++ modules


Future: Integrate cardano-serialization-lib or cardano-transaction-lib or paima-engine. Support Windows.


## How?

### Setup

[Install Nix](https://nixos.org/download.html), [enable flakes](https://nixos.wiki/wiki/Flakes#Installing_flakes), and [set up MLabs binary cache](https://github.com/mlabs-haskell/ci-example#set-up-binary-cache).

### Build

```
nix build
```


