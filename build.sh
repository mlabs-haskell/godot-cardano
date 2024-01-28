#!/bin/bash

cd libcsl_godot
cargo build
cd ../
cp libcsl_godot/target/debug/libcsl_godot.so 'addons/@mlabs-haskell/godot-cardano/bin/libcsl_godot.linux.template_debug.x86_64.so'
