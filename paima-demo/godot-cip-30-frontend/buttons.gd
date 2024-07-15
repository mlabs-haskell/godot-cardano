extends GridContainer

class_name Buttons

var _cip_30_wallet: Cip30WalletApi
var _game_middleware: GameMiddleware
var _window
var _godot_login_info: PaimaMiddleware.LoginInfo

# Buttons
var _login_button
var _join_button
var _player_pos_button
var _player_move_box = HBoxContainer.new()

func _init(
		cip_30_wallet: Cip30WalletApi, 
		godot_login_info: PaimaMiddleware.LoginInfo,
		window
	) -> void:
	_cip_30_wallet = cip_30_wallet
	_godot_login_info = godot_login_info
	_window = window

# Called when the node enters the scene tree for the first time.
func _ready():
	if _window && _window.paima_endpoints:
		print("init Paima")
		add_paima_game_buttons(_window.paima_endpoints)
	if _cip_30_wallet:
		add_test_sign_button()
#
func add_paima_game_buttons(paima_endpoints):
	_game_middleware = GameMiddleware.new(PaimaMiddleware.new(paima_endpoints))
	
	var sep1 = Label.new()
	sep1.text = "Paima buttons"
	sep1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep1)
	
	# Login
	_login_button = Button.new()
	_login_button.text = "Paima login with wallet"
	_login_button.pressed.connect(_game_middleware.login.bind(_godot_login_info))
	add_child(_login_button)
	
	# Join world
	_join_button = Button.new()
	_join_button.text = "Paima Join World"
	_join_button.pressed.connect(_game_middleware.join_world)
	_join_button.disabled = true
	add_child(_join_button)
	
	_add_movement_buttons()
	
	# Button to refresh and show player posiotion
	_player_pos_button = Button.new()
	_player_pos_button.text = "Player position: N/A"
	_player_pos_button.pressed.connect(_game_middleware.update_player_stats)
	_player_pos_button.disabled = true
	add_child(_player_pos_button)
	
	var sep2 = Label.new()
	sep2.text = "Paima debug buttons"
	sep2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep2)
	
	# Show Paima wallet
	var show_status_button = Button.new()
	show_status_button.text = "Show Paima status"
	show_status_button.pressed.connect(_game_middleware.show_status)
	add_child(show_status_button)
	


func _add_movement_buttons():
	
	# Step right
	var _step_right_button = Button.new()
	_step_right_button.text = "Step RIGHT"
	_step_right_button.pressed.connect(_move_to.bind(1, 0))
	_player_move_box.add_child(_step_right_button)
	
	# Step left
	var _step_left_button = Button.new()
	_step_left_button.text = "Step LEFT"
	_step_left_button.pressed.connect(_move_to.bind((-1), 0))
	
	# Step up
	var _step_up_button = Button.new()
	_step_up_button.text = "Step UP"
	_step_up_button.pressed.connect(_move_to.bind(0, 1))
	
	# Step up
	var _step_down_button = Button.new()
	_step_down_button.text = "Step DOWN"
	_step_down_button.pressed.connect(_move_to.bind(0, (-1)))
	
	_player_move_box.add_child(_step_right_button)
	_player_move_box.add_child(_step_left_button)
	_player_move_box.add_child(_step_up_button)
	_player_move_box.add_child(_step_down_button)
	
	add_child(_player_move_box)
	_disable_movement()
	#_player_move_box.hidden = true TODO

func _move_to(x, y):
	var new_x = _game_middleware.get_x() + x
	var new_y = _game_middleware.get_y() + y
	#prints("xy_args", xy_args)
	prints("new_x", new_x)
	prints("new_y", new_y)
	
	if (new_x < 0 || new_y < 0):
		print("Can't move out of the Open World map bounds")
		return
	_game_middleware.submit_moves(new_x, new_y)

func _disable_movement():
	for move_button in _player_move_box.get_children():
		move_button.disabled = true
		
func _enable_movement():
	for move_button in _player_move_box.get_children():
		move_button.disabled = false

func add_test_sign_button():
	var sep = Label.new()
	sep.text = "Godot wallet debug buttons"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep)
	var testSignB = Button.new()
	testSignB.text = "Test data sign"
	testSignB.pressed.connect(test_sing)
	add_child(testSignB)

func test_sing():
	const test_data = "godot-test"
	var test_hex = test_data.to_utf8_buffer().hex_encode()
	prints("Signing known test data - hex of", test_data, ": ", test_hex)
	
	prints("Test sig address hex: ", _cip_30_wallet.get_address())
	var key: String
	var signature: String
	## JavaScriptBridge always creates `null` object if not in the browser context
	if _window:
		print("Signing in browser env")
		var sign_res = _cip_30_wallet.sign_data("", test_hex)
		key = sign_res.key
		signature = sign_res.signature
	else:
		print("Signing in native env")
		var sign_res = _cip_30_wallet._single_address_wallet.sign_data("", test_hex)
		if sign_res.is_err():
			prints("Failed to sign data: ", sign_res.error)
			return
		key = sign_res.value._cose_key_hex()
		signature = sign_res.value._cose_sig1_hex()
		
	prints("Test sig COSE key: ", key)
	prints("Test sig COSE sig1: ", signature)

func sign_data(signing_address, payload):
	return 

var since_last_stats_refresh = 0 
var stats_refresh_period = 3 # seconds

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if _game_middleware:
		since_last_stats_refresh = since_last_stats_refresh + delta
		if since_last_stats_refresh > stats_refresh_period:
			since_last_stats_refresh = 0
			if _game_middleware._player_stats:
				_game_middleware.update_player_stats()
		if _game_middleware.wallet_is_set():
			_join_button.disabled = false
			_login_button.disabled = true
		if _game_middleware.has_player_stats():
			_player_pos_button.disabled = false
			_join_button.disabled = true
			_enable_movement()
			_player_pos_button.text = str(
				"Player position: x=", 
				_game_middleware.get_x(),
				", y=",
				_game_middleware.get_y(),
				)
		else:
			_disable_movement()
