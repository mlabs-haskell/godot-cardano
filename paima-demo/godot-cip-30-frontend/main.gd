extends Node2D

var window = JavaScriptBridge.get_interface("window")
var loader := SingleAddressWalletLoader.new(ProviderApi.Network.MAINNET)

var provider
var wallet
var buttons_grid
var ui_grid
var walet_picker: HBoxContainer 

# Called when the node enters the scene tree for the first time.
func _ready():
	print("GD: starting cardano-godot Paima demo")
	ui_grid = GridContainer.new()
	add_child(ui_grid)
	walet_picker = HBoxContainer.new()
	ui_grid.add_child(walet_picker)
	var seed_wallet_ui = SeedWalletUI.new()
	seed_wallet_ui.on_seed_received.connect(_init_godot_wallet)
	walet_picker.add_child(seed_wallet_ui)
	# TODO: if window
	var light_wallet_ui = LightWalletUI.new()
	light_wallet_ui.on_light_wallet_picked.connect(_init_light_wallet)
	walet_picker.add_child(light_wallet_ui)

func _init_light_wallet(name):
	var login_info := PaimaMiddleware.LoginInfo.new(
	name, 
	PaimaMiddleware.WalletMode.CARDANO, 
	true
	)
	print("_init_light_wallet init_buttons")
	init_buttons(login_info, null)
	_hide_wallet_picker()
	

func _init_godot_wallet(seedphrase):
	print("GD: Loading cardano wallet...")
	_remove_buttons()
	var load_result = await loader.import_from_seedphrase_wo_new_thread(
		seedphrase, "", "", 0, "Acc name", "Acc description"
		)
	if load_result.is_err():
		print("Failed to load cardano wallet with specified seed phrase")
		_remove_buttons()
		return
	wallet = load_result.value.wallet
	prints("GD: Godot wallet address bech32: ", wallet.get_address().to_bech32())
	prints("GD: Godot wallet address hex: ", wallet.get_address().to_hex())
	_on_godot_wallet_ready()

func _remove_buttons():
	if buttons_grid:
		ui_grid.remove_child(buttons_grid)
		buttons_grid = null

func _on_godot_wallet_ready():
	var cip_30_wrapper = Cip30SingleAddressWallet.new(wallet)
	var godot_login_info := PaimaMiddleware.LoginInfo.new(
	"godot", 
	PaimaMiddleware.WalletMode.CARDANO, 
	true
	)
	init_buttons(godot_login_info, cip_30_wrapper)
	Cip30Callbacks.new(cip_30_wrapper).add_to(window)
	_hide_wallet_picker()

func init_buttons(login_info: PaimaMiddleware.LoginInfo, cip_30_wallet: Cip30WalletApi):
	buttons_grid = Buttons.new(login_info, window, cip_30_wallet)
	buttons_grid.set_name("Buttons")
	ui_grid.add_child(buttons_grid)

func _hide_wallet_picker():
	ui_grid.remove_child(walet_picker)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass
