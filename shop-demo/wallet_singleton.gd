extends Node

# TODO: save and import as resource
var wallet: OnlineWallet.OnlineSingleAddressWallet = null

var provider: Provider = null

var user_funds: BigInt

const network := ProviderApi.Network.PREVIEW
const wallet_path := "user://user_wallet.tres"

signal wallet_ready

func _ready() -> void:
	user_funds = BigInt.zero()
	var single_address_wallet: SingleAddressWallet
	
	if FileAccess.file_exists(wallet_path):
		var import_result := await load_wallet()
		
		if import_result.is_err():
			push_error("Failed to import: %s" % import_result.error)
			get_tree().quit()
		
		single_address_wallet = import_result.value.wallet
	else:
		single_address_wallet = create_new_wallet()
		
	var blockfrost_api_key = FileAccess.get_file_as_string("res://preview_token.txt").strip_edges()
	var provider_api := BlockfrostProviderApi.new(
		network,
		blockfrost_api_key
	)
	add_child(provider_api)
	provider = Provider.new(provider_api)
	add_child(provider)
	wallet = OnlineWallet.OnlineSingleAddressWallet.new(single_address_wallet, provider)
	add_child(wallet)
	wallet.got_updated_utxos.connect(self._on_wallet_updated_utxos)
	provider.chain_address(wallet.get_address())
	provider.use_chaining = true
	provider.use_caching = true
	wallet_ready.emit()
	
	print("Using wallet %s" % wallet.get_address().to_bech32())

func _on_wallet_updated_utxos(_utxos: Array[Utxo]):
	if wallet == null:
		user_funds = BigInt.zero()
	else:
		user_funds = await wallet.total_lovelace()

func create_new_wallet() -> SingleAddressWallet:
	var new_wallet_result := SingleAddressWalletLoader.create(
		"1234",
		0,
		"My Account",
		"An account for my Cardano game",
		network
	)
	
	if new_wallet_result.is_err():
		push_error("Failed to create wallet: %s" % new_wallet_result.error)
		return
	
	var new_wallet := new_wallet_result.value.wallet
	
	ResourceSaver.save(new_wallet.export(), wallet_path)
	return new_wallet

func load_wallet() -> SingleAddressWalletLoader.WalletImportResult:
	var wallet_resource: SingleAddressWalletResource = load(wallet_path)
	var loader = SingleAddressWalletLoader.new(network)
	return await loader.import_from_resource(wallet_resource)

func load_wallet_from_seedphrase() -> SingleAddressWalletLoader.WalletImportResult:
	var seed_phrase = FileAccess.get_file_as_string("res://seed_phrase.txt")
	var loader := SingleAddressWalletLoader.new(ProviderApi.Network.PREVIEW)
	var import_result := await loader.import_from_seedphrase(
		seed_phrase,
		"",
		"1234",
		0,
		"My Account",
		"An account for my Cardano game"
	)
	return import_result
