extends Node2D

var window = JavaScriptBridge.get_interface("window")

var loader
var provider
var wallet
var buttons_grid
var ui_grid

# Called when the node enters the scene tree for the first time.
func _ready():
	print("GD: starting cardano-godot Paima demo")
	ui_grid = GridContainer.new()
	add_child(ui_grid)
	var set_seed_grid = SeedSetter.new()
	set_seed_grid.on_seed_received.connect(init_cardano_wallet)
	ui_grid.add_child(set_seed_grid)

func init_cardano_wallet(seedphrase):
	print("GD: Loading cardano wallet...")
	_remove_buttons()
	loader = SingleAddressWalletLoader.new(Provider.Network.MAINNET)
	add_child(loader)
	var load_result = await loader.import_from_seedphrase_wo_new_thread(
		seedphrase, "", "", 0, "Acc name", "Acc description"
		)
	if load_result.is_err():
		print("Failed to load cardano wallet")
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
	init_buttons()
	Cip30Callbacks.new(wallet).add_to(window)

func init_buttons():
	buttons_grid = Buttons.new(wallet, window)
	buttons_grid.set_name("Buttons")
	ui_grid.add_child(buttons_grid)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
