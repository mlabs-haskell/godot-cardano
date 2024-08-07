extends Node
# If `RefCounted` is used, then GDScript callbacks stop working - they are not called at all.
# Probably coz references to callbacks are lost (see below).
# (?) Alternative is to keep reference to `RefCounted` on root node (main.gd)

## Provides CIP-30 compliant functions for Godot wallet.
## Used to add GDScript callbacks wrapped with JavaScriptBridge into `window.cardano.godot` Object.
## Class `JsCip30Api` (`cip_30_js_api.gd`) contains JS script that creates `window.cardano.godot` Object
## and also wraps this callbacks one more time to return Promise result on the JS side
## as it is not clear how to get `return` value back from JavaScriptBridge callbacks
## (see https://forum.godotengine.org/t/getting-return-value-from-js-callback/54190/3)

class_name Cip30Callbacks

var _cip_30_wallet: Cip30WalletApi

# This references must be kept
# See example: https://docs.godotengine.org/en/stable/classes/class_javascriptobject.html#javascriptobject
var _js_cb_get_unused_addresses = JavaScriptBridge.create_callback(_cb_get_unused_addresses)
var _js_cb_get_used_addresses = JavaScriptBridge.create_callback(_cb_get_used_addresses)
var _js_cb_sign_data = JavaScriptBridge.create_callback(_cb_sign_data)

func _init(cip_30_wallet: Cip30WalletApi):
	_cip_30_wallet = cip_30_wallet

# TODO: CIP-30 compliant errors
# CIP-30 callbacks
## Adding to `window`
func add_to(window):
	if !window:
		print("GD: Browser 'window' not found - skip adding CIP-30 callbacks")
		return
	
	# JsCip30Api initiates `window.cardano.godot` Object where callbacks are added
	# so this step should be executed before setting GDScript callbacks
	JsCip30Api.new().init_cip_30_api()
	# Setting GDScript callbacks
	window.cardano.godot.callbacks.get_used_addresses = _js_cb_get_used_addresses
	window.cardano.godot.callbacks.get_unused_addresses = _js_cb_get_unused_addresses
	window.cardano.godot.callbacks.sign_data = _js_cb_sign_data
	print("GD: CIP-30 JS API initialization is done")

func _cb_get_used_addresses(args):
	prints("GD: _cb_get_used_addresses")
	var addresses = JavaScriptBridge.create_object("Array", 1)
	addresses[0] = _cip_30_wallet.get_address()
	var promise_resolve: JavaScriptObject = args[0]
	promise_resolve.call("call", promise_resolve.this, addresses)

func _cb_get_unused_addresses(args):
	var addresses = JavaScriptBridge.create_object("Array", 0)
	var promise_resolve: JavaScriptObject = args[0]
	promise_resolve.call("call", promise_resolve.this, addresses)

# TODO: CIP-30 sign errors
#DataSignErrorCode {
	#ProofGeneration: 1,
	#AddressNotPK: 2,
	#UserDeclined: 3,
#}
#type DataSignError = {
	#code: DataSignErrorCode,
	#info: String
#}
func _cb_sign_data(args):
	var promise_resolve: JavaScriptObject = args[0]
	var promise_reject: JavaScriptObject = args[1]
	var signing_address: String = args[2]
	var data_hex: String = args[3]
	
	# TODO: If we want proper CIP-30 support, we should parse the address (could be hex or bech32)
	# to pub key and differentiate between ProofGeneration and AddressNotPK errors
	
	# Paima framework will pass bech32 encoded Address into the sing request if the wallet is not Nami
	if !_cip_30_wallet.owns_address(signing_address):
		var sign_error = JavaScriptBridge.create_object("Object")
		sign_error.code = 1
		sign_error.info = "Wallet can't sign data - address does not belong to the wallet, or not properly encoded (expecting hex)"
		promise_reject.call("call", promise_reject.this, sign_error)
		return
	
	prints("GD:CIP-30:sign data:", "address: ", signing_address, ", data hex: ", data_hex)
	var sign_result = _cip_30_wallet.sign_data("", data_hex)
	promise_resolve.call("call", promise_resolve.this, sign_result)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
