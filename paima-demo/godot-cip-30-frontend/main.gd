extends Node2D

var window = JavaScriptBridge.get_interface("window")

const seedphrase: String = "camp fly lazy street predict cousin pen science during nut hammer pool palace play vague divide tower option relax need clinic chapter common coast"
const token: String = "[UNSET]"

var loader
var provider
var godot_wallet

# Called when the node enters the scene tree for the first time.
func _ready():
	init_cardano_wallet()

func init_cardano_wallet():
	print("GD: init_cardano_wallet")
	loader = SingleAddressWalletLoader.new(Provider.Network.MAINNET)
	provider = BlockfrostProvider.new(
		Provider.Network.MAINNET,
		token
	)
	add_child(loader)
	add_child(provider)
	var importRes = await loader.import_from_seedphrase_wo_new_thread(
		seedphrase, "", "", 0, "Acc name", "Acc description"
		)
	if importRes.is_err():
		print("Failed to load cardano wallet")
		return
	godot_wallet = Wallet.MnemonicWallet.new(importRes.value.wallet, provider)
	prints("GD: Godot wallet address bech32: ", godot_wallet.single_address_wallet.get_address().to_bech32())
	prints("GD: Godot wallet address hex: ", godot_wallet.single_address_wallet.get_address().to_hex())
	_on_godot_wallet_ready()

func _on_godot_wallet_ready():
	init_buttons()
	Cip30Callbacks.new(godot_wallet).add_to(window)

func init_buttons():
	var buttons = Buttons.new(godot_wallet, window)
	buttons.set_name("Buttons")
	add_child(buttons)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
