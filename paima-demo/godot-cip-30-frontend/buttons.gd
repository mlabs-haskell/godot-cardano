extends GridContainer

class_name Buttons

var _godot_wallet: SingleAddressWallet
var _paima_middleware
var _window

# Buttons
var login_button
var join_button
var step_right_button

var player_pos_button

func _init(godot_wallet: SingleAddressWallet, window):
	_godot_wallet = godot_wallet
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
	_paima_middleware = PaimaMiddleware.new(window)
	
	var sep1 = Label.new()
	sep1.text = "Paima buttons"
	sep1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep1)
	
	# Login
	login_button = Button.new()
	login_button.text = "Paima login with wallet"
	login_button.pressed.connect(_paima_middleware.login)
	add_child(login_button)
	
	# Join world
	join_button = Button.new()
	join_button.text = "Paima Join World"
	join_button.pressed.connect(_paima_middleware.join_world)
	join_button.disabled = true
	add_child(join_button)
	
	# Step right
	step_right_button = Button.new()
	step_right_button.text = "Step right"
	step_right_button.pressed.connect(test_step_right)
	step_right_button.disabled = true
	add_child(step_right_button)
	
	# Button to refresh and show player posiotion
	player_pos_button = Button.new()
	player_pos_button.text = "Player position: N/A"
	player_pos_button.pressed.connect(_paima_middleware.update_player_stats)
	player_pos_button.disabled = true
	add_child(player_pos_button)
	
	var sep2 = Label.new()
	sep2.text = "Paima debug buttons"
	sep2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sep2)
	
	# Show Paima wallet
	var showWalletB = Button.new()
	showWalletB.text = "Show Paima status"
	showWalletB.pressed.connect(_paima_middleware.show_status)
	add_child(showWalletB)

func test_step_right():
	# TODO: unsafe, but enough for tests - need to check world boundaries
	_paima_middleware.submit_moves(_paima_middleware.get_x() + 1, 0)

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
	if _paima_middleware:
		since_last_stats_refresh = since_last_stats_refresh + delta
		if since_last_stats_refresh > stats_refresh_period:
			since_last_stats_refresh = 0
			if _paima_middleware._player_stats:
				_paima_middleware.update_player_stats()
		
		if _paima_middleware._paima_wallet:
			join_button.disabled = false
			login_button.disabled = true
		if _paima_middleware.has_player_stats():
			player_pos_button.disabled = false
			join_button.disabled = true
			step_right_button.disabled = false
			player_pos_button.text = str(
				"Player position: x=", 
				_paima_middleware.get_x(),
				", y=",
				_paima_middleware.get_y(),
				)
