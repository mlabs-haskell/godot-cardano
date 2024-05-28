extends RefCounted

class_name PaimaMiddleware

var console = JavaScriptBridge.get_interface("console")

var _middleware
var _endpoints
var _paima_wallet
var _user_stats


#TODO: figure out endpoints type 
func _init(window) -> void:
	assert(window)
	print("PaimaMiddleware._init")
	_middleware = window.paima
	assert(_middleware)
	_endpoints = _middleware.endpoints
	assert(_endpoints)
#


## Login
### The func
func login():
	var godotWalletInfo = mk_wallet_info()
	prints("paima_login: godotWalletInfo: ", godotWalletInfo)
	_endpoints.userWalletLogin(godotWalletInfo).then(_on_login_js)

### Callback
var _on_login_js = JavaScriptBridge.create_callback(_on_login)
func _on_login(args):
	print("setting _paima_wallet")
	var wallet = args[0]
	_paima_wallet = wallet
	print("_paima_wallet set")
	update_user_stats()

## Join world
### The func
func join_world():
	_endpoints.joinWorld().then(_on_join_world_js)

### Callback
var _on_join_world_js = JavaScriptBridge.create_callback(_on_join_world)
func _on_join_world(args):
	print("setting _paima_wallet")
	console.log("Join world res ", args[0])
	
## Update status
### The func
func update_user_stats():
	if _paima_wallet && _paima_wallet.success:
		prints("GD: getting user stats")
		_endpoints.getUserStats(_paima_wallet.result.walletAddress).then(_on_stats_received_js)
	else:
		print("GD: wallet login was usuccessfull, check wallet by `show wallet` buttion")

### Callback
var _on_stats_received_js = JavaScriptBridge.create_callback(_on_stats_received)
func _on_stats_received(args):
	_user_stats = args[0]
	console.log("User stats ", args[0])

## Submit moves
### The func
func submit_moves(x, y):
	prints("wallet success: ", _paima_wallet.success)
	_endpoints.submitMoves(x, y).then(_on_moves_submitted_js)

### Callback
var _on_moves_submitted_js = JavaScriptBridge.create_callback(_on_moves_submitted)
func _on_moves_submitted(args):
	console.log("Moves submit result ", args[0])

## Show wallet
func show_wallet():
	console.log("Paima wallet: ", _paima_wallet)


## Helpers

func get_x(): # TODO: null handling
	return _user_stats.stats.x
	
func get_y(): # TODO: null handling
	return _user_stats.stats.y

## TODO: looks like we'll need to inject our own `cardano` object if there is no ohter wallets in browser
func mk_wallet_info():
	var pref = new_js_obj()
	pref.name = "godot"
	var info = new_js_obj()
	info.mode = 3 #todo: defines WalletMode.Cardano in Paima, how can it be puleld out of there?
	info.preferBatchedMode = true
	info.preference = pref
	return info
	
func new_js_obj():
	return JavaScriptBridge.create_object("Object")
