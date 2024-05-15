extends Node

# TODO: save and import as resource
var wallet: Wallet.MnemonicWallet = null

var cardano: Cardano = null
var provider: BlockfrostProvider = null

var user_funds: BigInt

signal wallet_ready

func _ready() -> void:
	user_funds = BigInt.zero()
	var seed_phrase := FileAccess.get_file_as_string("res://seed_phrase.txt")
	var wallet_loader := SingleAddressWalletLoader.new()
	var import_result := await wallet_loader.import_from_seedphrase(
		seed_phrase,
		"",
		"1234",
		0,
		"My Wallet",
		""
	)
	
	if import_result.is_err():
		push_error("Failed to import: %s" % import_result.error)
		get_tree().quit()
	
	var blockfrost_api_key = FileAccess.get_file_as_string("res://preview_token.txt").strip_edges()
	provider = BlockfrostProvider.new(
		Provider.Network.PREVIEW,
		blockfrost_api_key
	)
	add_child(provider)
	wallet = Wallet.MnemonicWallet.new(import_result.value.wallet, provider)
	add_child(wallet)
	cardano = Cardano.new(wallet, provider)
	add_child(cardano)
	wallet.got_updated_utxos.connect(self._on_wallet_updated_utxos)
	wallet_ready.emit()

func _on_wallet_updated_utxos(utxos: Array[Utxo]):
	if wallet == null:
		user_funds = BigInt.zero()
	else:
		user_funds = await wallet.total_lovelace()
