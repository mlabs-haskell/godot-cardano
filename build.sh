#!/bin/bash

cd libcsl_godot
cargo build
cd ../
cp libcsl_godot/target/debug/libcsl_godot.so csl_demo/bin/libcsl_godot.linux.template_debug.x86_64.so
