extends RefCounted
class_name PaimaMiddleware

## Wrapper for the core of Paima middleware.
## 
## Provides API for logging-in and querying the `RoundExecutor`.[br][br]
##
## This API deals mostly with objects from the Paima middleware, and hence uses
## [JavaScriptObject]s for many different things. Most importantly, the API is
## initialized with the [code]paima_endpoints[/code] object, injected by Paima in the
## browser window. This object can be retrieved with the [method get_endpoints],
## allowing the user to manually interact with the Paima endpoints using the
## Javascript interface (check [method get_endpoints] documentation for more details).[br][br]
##
## Most methods exposed in this API are asynchronous. As such, they can be [code]await[/code]ed
## or a callback can be bound to their respective signals.

## Wallet mode
##
## The kind of wallet to be used when logging into Paima.
enum WalletMode  { 
	EVM_INJECTED = 0, 
	EVM_ETHERS = 1,
	EVM_TRUFFLE = 2,
	CARDANO = 3,
	POLKADOT = 4,
	ALGORAND =5
	}

## Login information
##
## Used in [method PaimaMiddleware.login]
class LoginInfo:
	var _wallet_name: String
	var _mode: WalletMode
	var _prefer_batcher: bool
	
	## Create [PaimaMiddleware.LoginInfo] by providing a [param wallet_name], a [param mode] and a
	## [param prefer_batcher_flag].[br][br]
	## For Cardano wallets, [param prefer_batcher] should always be set
	## to [code]true[/code], as they can only work through the Paima batcher.
	func _init(
		wallet_name: String, 
		mode: WalletMode, 
		prefer_batcher: bool
	) -> void:
		_wallet_name = wallet_name
		_mode = mode
		_prefer_batcher = prefer_batcher

var _endpoints: JavaScriptObject
var _paima_wallet: JavaScriptObject

## The browser console, provided here for convenience
var console := JavaScriptBridge.get_interface("console")

## A [PaimaMiddleware] is initialized by providing an [param endpoints]
## object, which is normally available under the `window` object[br][br]
## [code]var endpoints = JavaScriptBridge.get_interface("window").paima_endpoints[/code][br]
## [code]var middleware = PaimaMiddleware(endpoints)
func _init(endpoints: JavaScriptObject) -> void:
	_endpoints = endpoints
	assert(_endpoints)

## Get the middleware endpoints, which can be used for executing middleware functions.[br]
## The core functions are already wrapped by [PaimaMiddleware] in a more convenient form,
## use this function for wrapping endpoints [b]not[/b] provided by the class (i.e: endpoints specific to
## your game).[br][br]
##
## For example, if you want to execute a [code]join_match[/code] function:[br][br]
##
## First, you define a GDScript callback you want to run after joining the match[br]
## [code]function join_match_cb(join_result: JavaScriptObject) -> void:[/code][br]
## [code]    ...[/code][br][br]
##
## Then, you wrap the GDScript callback in a Javascript callback using [method JavasScriptBridge.create_callback][br]
## [code]var join_match_cb_js := JavaScriptBridge.create_callback(join_match_cb)[/code][br][br]
##
## Finally, you get the the endpoints object and execute [code]join_match[/code]. The return value
## will be a promise to which you can attach your Javascript callback using the Promise API.[br]
## [code]middleware.get_endpoints().join_match(...).then()[/code]
func get_endpoints() -> JavaScriptObject:
	return _endpoints

## Get the wallet being used by the Paima middleware
func get_wallet() -> JavaScriptObject:
	return _paima_wallet

## Get the wallet address 
# TODO: Provide a return type for this function?
func get_wallet_address():
	return _paima_wallet.result.walletAddress

## Log into Paima using [param login_info].
func login(login_info: LoginInfo) -> bool:
	var js_login_info = _to_js_login_info(login_info)
	console.log("GD:Paima: login_info: ", js_login_info)
	_endpoints.userWalletLogin(js_login_info).then(_on_login_js)
	var login_successful = await on_paima_login
	return login_successful

## Emitted by [method login]
signal on_paima_login(success: bool)

# Callback
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

## Returns [code]true[/code] if a wallet was successfully set for the Paima
## middleware.
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

## Query the state of the round executor by providing a [parama lobby_id] and
## a [param round_number].
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

# JS callback
var _on_executor_query_response_js = JavaScriptBridge.create_callback(_on_executor_query_response)
func _on_executor_query_response(args) -> void:
	on_executor_response.emit(args[0])

## Emitted by [method query_round_executor]
signal on_executor_response(re_result: JavaScriptObject)

func _new_js_obj() -> JavaScriptObject:
	return JavaScriptBridge.create_object("Object")
