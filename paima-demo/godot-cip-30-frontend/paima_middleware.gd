extends RefCounted

class_name PaimaMiddleware

var console = JavaScriptBridge.get_interface("console")

var _middleware # JS Object
var _endpoints # JS Object
var _paima_wallet # JS Object
var _player_stats # JS Object

#TODO: figure out endpoints type 
func _init(window) -> void:
	assert(window)
	_middleware = window.paima
	assert(_middleware)
	_endpoints = _middleware.endpoints
	assert(_endpoints)

## Login
### The func
func login():
	var godot_wallet_info = mk_wallet_info()
	console.log("GD:Paima: godotWalletInfo: ", godot_wallet_info)
	_endpoints.userWalletLogin(godot_wallet_info).then(_on_login_js)

### Callback
var _on_login_js = JavaScriptBridge.create_callback(_on_login)
func _on_login(args):
	var wallet = args[0]
	if wallet && wallet.success:
		_paima_wallet = wallet
		print("GD:Paima: paima_wallet set")
		update_player_stats()
	else:
		prints("GD:Paima: Paima login error: wallet not set!")
		console.log("Paima wallet login result:", wallet)

## Join world
### The func
func join_world():
	_endpoints.joinWorld().then(_on_join_world_js)

### Callback
var _on_join_world_js = JavaScriptBridge.create_callback(_on_join_world)
func _on_join_world(args):
	console.log("GD:Paima: join world result: ", args[0])
	
## Update status
### The func
func update_player_stats():
	if _wallet_is_set():
		_endpoints.getUserStats(_paima_wallet.result.walletAddress).then(_on_stats_received_js)
	else:
		print("GD:Paima: wallet login was usuccessfull, check wallet by `show wallet` buttion")

### Callback
var _on_stats_received_js = JavaScriptBridge.create_callback(_on_stats_received)
func _on_stats_received(args):
	_player_stats = args[0]

## Submit moves
### The func
func submit_moves(x, y):
	_endpoints.submitMoves(x, y).then(_on_moves_submitted_js)

### Callback
var _on_moves_submitted_js = JavaScriptBridge.create_callback(_on_moves_submitted)
func _on_moves_submitted(args):
	console.log("GD:Paima: Moves submit result ", args[0])

## Show wallet
func show_status():
	console.log("GD:Paima: Paima wallet: ", _paima_wallet)
	console.log("GD:Paima: Paima player stats: ", _player_stats)
	

## Helpers
func has_player_stats():
	return _player_stats && _player_stats.stats

func _wallet_is_set():
	return  _paima_wallet && _paima_wallet.success

func get_x(): # TODO: null handling
	return _player_stats.stats.x
	
func get_y(): # TODO: null handling
	return _player_stats.stats.y

func mk_wallet_info():
	var pref = new_js_obj()
	# TODO: pass this vars as arguments
	pref.name = "godot"
	var info = new_js_obj()
	info.mode = 3
	info.preferBatchedMode = true
	info.preference = pref
	return info
	
func new_js_obj():
	return JavaScriptBridge.create_object("Object")
