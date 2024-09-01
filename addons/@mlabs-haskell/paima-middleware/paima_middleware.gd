extends RefCounted
class_name PaimaMiddleware

## Wrapper for core of Paima middleware.
## 
## Provides API for logging-in and querying `RoundExecutor`.
## All calls wrap JS object with Paima middleware. Handling of JS Promises is done
## via signals and `await`s.

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

var _endpoints: JavaScriptObject
var _paima_wallet: JavaScriptObject

var console = JavaScriptBridge.get_interface("console")

func _init(endpoints: JavaScriptObject) -> void:
	_endpoints = endpoints
	assert(_endpoints)

func get_endpoints() -> JavaScriptObject:
	return _endpoints
	
func get_wallet() -> JavaScriptObject:
	return _paima_wallet

func get_wallet_address():
	return _paima_wallet.result.walletAddress

## Login
### The func
func login(login_info: LoginInfo, on_login_cb = null) -> bool:
	var js_login_info = _to_js_login_info(login_info)
	console.log("GD:Paima: login_info: ", js_login_info)
	_endpoints.userWalletLogin(js_login_info).then(_on_login_js)
	var login_successful = await on_paima_login
	return login_successful

### Signal for `await`
signal on_paima_login(success: bool)

### Callback
var _on_login_js = JavaScriptBridge.create_callback(_on_login)
func _on_login(args) -> void:
	var wallet = args[0]
	if wallet && wallet.success:
		_paima_wallet = wallet
		print("GD:Paima: paima_wallet set")
		on_paima_login.emit(true)
	else:
		prints("GD:Paima: Paima login error: wallet not set!")
		console.log("Paima wallet login result:", wallet)
		on_paima_login.emit(false)

func wallet_is_set() -> bool:
	return  _paima_wallet && _paima_wallet.success

func _to_js_login_info(login_info: LoginInfo) -> JavaScriptObject:
	var pref = _new_js_obj()
	pref.name = login_info._wallet_name
	var info = _new_js_obj()
	info.mode = login_info._mode
	info.preferBatchedMode = login_info._prefer_batcher
	info.preference = pref
	return info

## Query round executor
### The func
func query_round_executor(lobby_id: String, round_number: int) -> RoundExecutor:
	_endpoints.getRoundExecutor(lobby_id, round_number).then(_on_executor_query_response_js)
	var re = await on_executor_response
	var executor
	if re.success:
		executor = RoundExecutor.new(re.result)
	else:
		console.error("GD:Paima: Failed to query RoundExecutor")
		executor = null
	return executor

### JS callback
var _on_executor_query_response_js = JavaScriptBridge.create_callback(on_executor_query_response)
func on_executor_query_response(args) -> void:
	on_executor_response.emit(args[0])

### Signal for `await`
signal on_executor_response(re_result: JavaScriptObject)

func _new_js_obj() -> JavaScriptObject:
	return JavaScriptBridge.create_object("Object")
