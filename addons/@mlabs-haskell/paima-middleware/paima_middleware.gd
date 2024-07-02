extends RefCounted

class_name PaimaMiddleware

enum WalletMode  { 
	EVM_INJECTED = 0, 
	EVM_ETHERS = 1,
	EVM_TRUFFLE = 2,
	CARDANO = 3,
	POLKADOT = 4,
	ALGORAND =5
	}

class LoginInfo:
	var _wallet_name: String
	var _mode: int
	var _prefer_batcher: bool
	
	## For Cardano wallets `prefer_batcher` should be set to `true` 
	## as they can work only through Paima barcher
	func _init(
		wallet_name: String, 
		mode: int, 
		prefer_batcher: bool
	) -> void:
		_wallet_name = wallet_name
		_mode = 	mode
		_prefer_batcher = prefer_batcher

var _middleware # JS Object
var _endpoints # JS Object
var _paima_wallet # JS Object

var console = JavaScriptBridge.get_interface("console")

func _init(window) -> void:
	assert(window)
	#_inject_self_to_window() #TODO
	_middleware = window.paima
	assert(_middleware)
	_endpoints = _middleware.endpoints
	assert(_endpoints)

func _inject_self_to_window():
	JavaScriptBridge.eval("""
	import endpoints, { WalletMode } from './paima/paimaMiddleware.js';
	const {parse} = require('node-html-parser');
	window.pppaima = {
			endpoints: endpoints,
		}
	""", true)

func get_enpoints():
	return _endpoints
	
func get_wallet():
	return _paima_wallet

func get_wallet_address():
	return _paima_wallet.result.walletAddress
	
## Login
### The func
func login(login_info: LoginInfo):
	var js_login_info = _to_js_login_info(login_info)
	console.log("GD:Paima: login_info: ", js_login_info)
	_endpoints.userWalletLogin(js_login_info).then(_on_login_js)

### Callback
var _on_login_js = JavaScriptBridge.create_callback(_on_login)
func _on_login(args):
	var wallet = args[0]
	if wallet && wallet.success:
		_paima_wallet = wallet
		print("GD:Paima: paima_wallet set")
	else:
		prints("GD:Paima: Paima login error: wallet not set!")
		console.log("Paima wallet login result:", wallet)

func wallet_is_set():
	return  _paima_wallet && _paima_wallet.success

func _to_js_login_info(login_info: LoginInfo):
	print("here 1")
	var pref = _new_js_obj()
	pref.name = login_info._wallet_name
	var info = _new_js_obj()
	info.mode = login_info._mode
	info.preferBatchedMode = login_info._prefer_batcher
	info.preference = pref
	return info
	
func _new_js_obj():
	return JavaScriptBridge.create_object("Object")
