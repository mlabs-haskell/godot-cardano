extends RefCounted

## Middleware specific to "Open World" game, built with `PaimaMiddleware` addon class.
## Unlike `PaimaMiddleware`, there is no `await` API for calls that wraps JS Promises here.
## Instead only callbacks created with JavaScriptBridge are used to mutate internal state.
## Internal state is then used in the `_process(...)` of the parent node to adjust UI.
class_name GameMiddleware

var console: JavaScriptObject = JavaScriptBridge.get_interface("console")
var _player_stats: JavaScriptObject
var _middleware: PaimaMiddleware
var _endpoints: JavaScriptObject

func _init(paima_middleware: PaimaMiddleware) -> void:
	_middleware = paima_middleware
	assert(_middleware)
	_endpoints = _middleware.get_endpoints()

## Login
### The func
func login(login_info: PaimaMiddleware.LoginInfo):
	var login_successful = await _middleware.login(login_info)
	if login_successful:
		console.log("GD:Paima: Game login successful. Checking player stats")
		# To handle the case when there is already game state exists for the wallet
		update_player_stats()
	else:
		console.warn("GD:Paima: Game login failed!")

## Join world
### The func
func join_world():
	console.log("GD:Paima: Joining game world...")
	_endpoints.joinWorld().then(_on_join_world_js)

### Callback
var _on_join_world_js = JavaScriptBridge.create_callback(_on_join_world)
func _on_join_world(args):
	console.log("GD:Paima: join world result: ", args[0])
	update_player_stats()
	
## Update status
### The func
func update_player_stats():
	if _middleware.wallet_is_set():
		_endpoints.getUserStats(_middleware.get_wallet_address()).then(_on_stats_received_js)
	else:
		print("GD:Paima: wallet login was not successful, check wallet by `show wallet` button")

# Callback
var _on_stats_received_js = JavaScriptBridge.create_callback(_on_stats_received)
func _on_stats_received(args):
	_player_stats = args[0]

## Submit moves
### The func
func submit_moves(x, y):
	console.log("GD:Paima: Submitting move...")
	_endpoints.submitMoves(x, y).then(_on_moves_submitted_js)

### Callback
var _on_moves_submitted_js = JavaScriptBridge.create_callback(_on_moves_submitted)
func _on_moves_submitted(args):
	console.log("GD:Paima: Moves submit result ", args[0])

## Show wallet
func show_status():
	console.log("GD:Paima: Paima wallet: ", _middleware.get_wallet())
	console.log("GD:Paima: Paima player stats: ", _player_stats)
	
func wallet_is_set():
	return _middleware.wallet_is_set()

## Helpers
func has_player_stats():
	return _player_stats && _player_stats.stats

func get_x():
	return _player_stats.stats.x
	
func get_y():
	return _player_stats.stats.y
