extends Node
# If `RefCounted` is used, then GDScript callbacks stop working - they are not called at all.
# Probably coz references to callbacks are lost (see below).
# (?) Alternative is to keep reference to `RefCounted` on root node (main.gd)

## Provides CIP-30 compliant functions for Godot wallet.
## Used to add GDScript callbacks wrapped with JavaScriptBridge into `window.cardano.godot` Object.
## res://extra-resources/cip-30-paima-shell.html contains JS script that creates `window.cardano.godot` Object
## and also wraps this callbacks one more time to return Promise result on the JS side
## as it is not clear how to get `return` value back from JavaScriptBridge callbacks
## (see https://forum.godotengine.org/t/getting-return-value-from-js-callback/54190/3)

class_name Cip30Callbacks
var _godot_wallet

# This references must be kept
# See example: https://docs.godotengine.org/en/stable/classes/class_javascriptobject.html#javascriptobject
var _js_cb_get_unused_addresses = JavaScriptBridge.create_callback(_cb_get_unused_addresses)
var _js_cb_get_used_addresses = JavaScriptBridge.create_callback(_cb_get_used_addresses)
var _js_cb_sign_data = JavaScriptBridge.create_callback(_cb_sign_data)

func _init(godot_wallet):
	_godot_wallet = godot_wallet

# TODO: CIP-30 compliant errors
# CIP-30 callbacks
## Adding to `window`
func add_to(window):
	if !window:
		print("GD: Browser 'window' not found - skip adding CIP-30 callbacks")
		return
	# `window.cardano.godot` Object is created via custom HTML shell and expected to be not null
	# see res://extra-resources/cip-30-paima-shell.html
	window.cardano.godot.callbacks.get_used_addresses = _js_cb_get_used_addresses
	window.cardano.godot.callbacks.get_unused_addresses = _js_cb_get_unused_addresses
	window.cardano.godot.callbacks.sign_data = _js_cb_sign_data
	print("GD: adding CIP-30 callbacks to `window.cardano.godot.callbacks` is done")

func _cb_get_used_addresses(args):
	prints("GD: _cb_get_used_addresses")
	var addresses = JavaScriptBridge.create_object("Array", 1)
	addresses[0] = _godot_wallet.single_address_wallet.get_address().to_hex()
	var promise_callback: JavaScriptObject = args[0]
	promise_callback.call("call", promise_callback.this, addresses)

func _cb_get_unused_addresses(args):
	var addresses = JavaScriptBridge.create_object("Array", 0)
	var promise_callback: JavaScriptObject = args[0]
	promise_callback.call("call", promise_callback.this, addresses)

func _cb_sign_data(args):
	prints("GD: _cb_sign_data")
	var promise_callback: JavaScriptObject = args[0]
	var signing_address: String = args[1]
	var bytes_hex: String = args[2]
	var sign_res = _godot_wallet.single_address_wallet.sign_data("", signing_address, bytes_hex)
	var signResult = JavaScriptBridge.create_object("Object")
	signResult.key = sign_res.value._cose_key_hex()
	signResult.signature = sign_res.value._cose_sig1_hex()
	promise_callback.call("call", promise_callback.this, signResult)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
