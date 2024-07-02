extends GridContainer

class_name Buttons

var _godot_wallet: SingleAddressWallet
var _game_middleware: GameMiddleware
var _window
var _godot_login_info

# Buttons
var _login_button
var _join_button
var _step_right_button
var _player_pos_button

func _init(
		godot_wallet: SingleAddressWallet, 
		godot_login_info: PaimaMiddleware.LoginInfo,
		window
	) -> void:
	_godot_wallet = godot_wallet
	_godot_login_info = godot_login_info
	_window = window

# Called when the node enters the scene tree for the first time.
func _ready():
	if _window && _window.paima:
		print("init Paima")
		add_paima_game_buttons(_window)
	if _godot_wallet:
		add_test_sign_button()
#
func add_paima_game_buttons(window):
	_game_middleware = GameMiddleware.new(PaimaMiddleware.new(window))
	
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
	
	# Step right
	_step_right_button = Button.new()
	_step_right_button.text = "Step right"
	_step_right_button.pressed.connect(test_step_right)
	_step_right_button.disabled = true
	add_child(_step_right_button)
	
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

func test_step_right():
	# TODO: unsafe, but enough for tests - need to check world boundaries
	_game_middleware.submit_moves(_game_middleware.get_x() + 1, 0)

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
	
	var signing_address = _godot_wallet.get_address_bech32()
	prints("Test sig address hex: ", _godot_wallet.get_address_hex())
	prints("Test sig address bech32: ", signing_address)
	var sign_res = sign_data(signing_address, test_hex)
	if sign_res.is_err():
		prints("Failed to sign data: ", sign_res.error)
		return
	prints("Test sig COSE key: ", sign_res.value._cose_key_hex())
	prints("Test sig COSE sig1: ", sign_res.value._cose_sig1_hex())

func sign_data(signing_address, payload):
	return _godot_wallet.sign_data("", payload);

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
			_step_right_button.disabled = false
			_player_pos_button.text = str(
				"Player position: x=", 
				_game_middleware.get_x(),
				", y=",
				_game_middleware.get_y(),
				)
