# Godot-cardano and Paima's "Open World" prototype

- [Godot-cardano and Paima's "Open World" prototype](#godot-cardano-and-paimas-open-world-prototype)
  - [Prerequisites](#prerequisites)
  - [Setting up the demo](#setting-up-the-demo)
    - [Add `addons`](#add-addons)
    - [Compile WASM](#compile-wasm)
    - [Generate and setup Paima template and Batcher](#generate-and-setup-paima-template-and-batcher)
    - [Export Godot demo project](#export-godot-demo-project)
  - [Running the demo](#running-the-demo)
    - [Start Paima node and required infrastructure](#start-paima-node-and-required-infrastructure)
    - [Starting frontend](#starting-frontend)
  - [Notes](#notes)
  - [TODO](#todo)

This is combination of Paima's "open-world" template and Godot project that serves for testing interactions between web-exported Godot project and Paima middleware.

## Prerequisites

- `Docker` (required to start testnet an other infra for Paima)
- `paima-engine`. Tested with `paima-engine-linux-2.3.0`).
- Rust (nightly). Tested with `cargo 1.77.1 (e52e36006 2024-03-26)`.
- `emscripten` for WASM and WEB-export. See [Godot-rust book](https://godot-rust.github.io/book/toolchain/export-web.html). Tested with `emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 3.1.39 (36f871819b566281d160470a1ec4515f379e9f77)`)
- `node` and `npm` - used a lot by Paima setup (see [Makefile](./Makefile) and generated Paima READMEs). Tested with `node v20.12.2` and `npm 10.5.0`
- Godot. Tested with `Godot_v4.2.1-stable_linux.x86_64` (extra flag that I had tu use: `--rendering-driver opengl3`). [WEB-export docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- `python` - to run web-server with required CORS headers (script taken from [godot manual `Tip` section](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#serving-the-files))

`node`, `npm` and `python` are available via `flake.nix` in the root of the current dir.

## Setting up the demo

### Add `addons`

1. Link or copy `addons` to `paima-demo/godot-cip-30-frontend`

### Compile WASM

1. `cd libcsl_godot`
2. Make sure emscripten is in PATH: `emcc --version`
3. `cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten`
4. Copy or link `libcsl_godot/target/wasm32-unknown-emscripten/debug/csl_godot.wasm` to `addons/@mlabs-haskell/godot-cardano/bin`

### Generate and setup Paima template and Batcher

From fresh repo proceed with following steps:

1. Copy or link to root paima engine as `paima-engine`
2. `make init` (goes through initialization process according to the [open-world-readme](./open-world/README.md); tested in Linux,some extra flags are required for macOS, see the readme; if there is some "red" messages about vulnerabilities it should be ok
3. `make replace-env-file`. ⚠️ This command changes `.env.localhost`, generated from `./open-world/.env.example`, to properly edited version - `.env.localhost.godot`. It adds proper `BATCHER_URI`, fixes `BATCHER_DB_HOST` (see generated [open-world/.env.example](./open-world/.env.example) for comparison). It is important to make this replace before the next one, or the middleware that will be built next, will miss some important settings.
4. `make paima-middleware`
5. `make init-batcher` - requests `sudo` to make batcher script (`./batcher/start.sh`) executable. ⚠️ `./batcher/.env.localhost` also changed according to `.env.localhost.godot`
6. `make webserver-dir`
7. `make distribute-middleware`

### Export Godot demo project

1. Open `godot-cip-30-frontend` in Godot
2. Set Blockfrost token in `paima-demo/godot-cip-30-frontend/main.gd` - look for `const token: String = "[UNSET]"`. Token should be for `mainnet` as Paima currnetly supports only `mainnet` addresses
3. Do web-export to `paima-demo/web-server/godot-web-export/index.html`. The project already have web-export config, but just in case make sure that in the web-export form:
   1. `Custom HTML Shell` is set to `res://extra-resources/cip-30-paima-shell.html`
   2. `Extensions Support` is `On`

## Running the demo

### Start Paima node and required infrastructure

ℹ️ Following commands require Docker and `node + npm`

1. `make start-db` (will keep running in  terminal)
2. `make start-chain` (will keep running in  terminal)
3. `make deploy-contracts`
4. `make start-paima-node` (will keep running in  terminal)
5. `make start-batcher` (will keep running in  terminal)

### Starting frontend

1. `make godot-website` - will start website on `8060`. The demo can be accessed at `http://localhost:8060/index.html`

## Notes

1. Any changes to Paima middleware and realated packages source code should be followed by `make paima-middleware` and `make distribute-middleware`

## TODO

- [ ] Docs about calling JS Promice's callback in GDScript callback to reposnd CIP-30 queries, if no better way will be found
- [ ] Docs about custom HTML shell
- [ ] Figure out multithreading to not to block main loop
- [ ] CIP-30 compliant errors
