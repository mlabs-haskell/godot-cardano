# Web export notes

[Web export guide](https://godot-rust.github.io/book/toolchain/export-web.html)

## Snippets

### Compilation

```bash
source "/home/mike/dev/mlabs/godot-wallet-project/emsdk/emsdk_env.sh"    
emcc --version && cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten
```
