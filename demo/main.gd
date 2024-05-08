extends Node2D

var provider: Provider
var cardano: Cardano = null
var wallet: Wallet.MnemonicWallet = null
var correct_password: String = ""
var loader := SingleAddressWalletLoader.new(Provider.Network.PREVIEW)

@onready
var wallet_details: RichTextLabel = %WalletDetails
@onready
var address_input: LineEdit = %AddressInput
@onready
var amount_input: LineEdit = %AmountInput
@onready
var password_input: LineEdit = $SendAdaForm/Password/PasswordInput
@onready
var password_warning: Label =  $SendAdaForm/Password/Status
@onready
var phrase_input: TextEdit = %PhraseInput
@onready
var timers_details: Label = %WalletTimers
@onready
var send_ada_button: Button = %SendAdaButton
@onready
var mint_token_button: Button = %MintTokenButton
@onready
var create_script_output_button: Button = %CreateScriptOutput
@onready
var consume_script_input_button: Button = %ConsumeScriptInput
@onready
var set_button: Button = %SetButton
@onready
var generate_button: Button = %GenerateButton

var test_spend_script: PlutusScript = PlutusScript.create("581b0100003222253330043330043370e900124008941288a4c2cae681".hex_decode())

func _ready() -> void:
	var token : String = FileAccess\
		.open("./preview_token.txt", FileAccess.READ)\
		.get_as_text(true)\
		.replace("\n", "")

	provider = BlockfrostProvider.new(
		Provider.Network.PREVIEW,
		token
	)
	add_child(provider)
	add_child(loader)
	wallet_details.text = "No wallet set"
	
	# if a seed phrase file is available, we load the seed phrase from there
	var seed_phrase_file := FileAccess.open("./seed_phrase.txt", FileAccess.READ)
	if seed_phrase_file != null:
		phrase_input.text = seed_phrase_file.get_as_text(true)
		_create_wallet_from_seedphrase(phrase_input.text)

func _process(_delta: float) -> void:
	if wallet != null:
		timers_details.text = "Timer: %.2f" % wallet.time_left
		timers_details.text += "\nSlot: %d" % cardano.time_to_slot(Time.get_unix_time_from_system())

func _on_wallet_set() -> void:
	var _ret := self.wallet.got_updated_utxos.connect(_on_utxos_updated)
	var addr := wallet._get_change_address().to_bech32()
	wallet_details.text = "Using wallet %s" % addr
	address_input.text = addr

func _on_utxos_updated(utxos: Array[Utxo]) -> void:
	var num_utxos := utxos.size()
	var total_lovelace : BigInt = utxos.reduce(
		func (acc: BigInt, utxo: Utxo) -> BigInt: return acc.add(utxo.coin()),
		BigInt.zero()
	)
	wallet_details.text = "Using wallet %s" % cardano.wallet._get_change_address().to_bech32()
	if num_utxos > 0:
		wallet_details.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]
		send_ada_button.disabled = false
		mint_token_button.disabled = false
		create_script_output_button.disabled = false
		consume_script_input_button.disabled = false

func _on_set_wallet_button_pressed() -> void:
	_create_wallet_from_seedphrase(phrase_input.text)

func _on_generate_new_wallet_pressed():	
	var old_text := set_button.text
	generate_button.text = "Generating wallet..."
	set_button.disabled = true
	generate_button.disabled = true
	var create_result := SingleAddressWalletLoader.create(
		password_input.text,
		0,
		"",
		"",
		Provider.Network.PREVIEW
	)
	if create_result.is_ok():	
		phrase_input.text = create_result.value.seed_phrase
		set_wallet(create_result.value.wallet)
	else:
		push_error("Creating wallet failed: %s" % create_result.error)
	set_button.text = old_text
	set_button.disabled = false
	generate_button.disabled = false
		
func _on_send_ada_button_pressed() -> void:
	var amount_result: BigInt.ConversionResult = BigInt.from_str(amount_input.text)
	
	if amount_result.is_err():
		push_error("There was an error while parsing the amount as a BigInt", amount_result.error)
		return
		
	var address_result := Address.from_bech32(address_input.text)
	
	if address_result.is_err():
		push_error("There was an error while parsing the address: %s", address_result.error)
		return
		
	var create_tx_result := cardano.new_tx()
	
	if create_tx_result.is_err():
		push_error("There was an error while creating the transaction: %s", create_tx_result.error)
		return
		
	var tx := create_tx_result.value
	tx.pay_to_address(
		address_result.value,
		amount_result.value,
		MultiAsset.empty()
	)
	tx.valid_after(Time.get_unix_time_from_system() - 120)
	tx.valid_before(Time.get_unix_time_from_system() + 180)
	var result := await tx.complete()
	
	if result.is_ok():
		result.value.sign(password_input.text)
		var submit_result = await result.value.submit()
		if submit_result.is_err():
			print('Failed to submit transaction: %s' % submit_result.error)
		else:
			await provider.await_tx(submit_result.value)

func _on_mint_token_button_pressed() -> void:
	var address := Address.from_bech32(address_input.text)
	var create_tx_result := cardano.new_tx()
	
	if create_tx_result.is_err():
		push_error("There was an error while creating the transaction: %s", create_tx_result.error)
		return
		
	var tx := create_tx_result.value
	tx.mint_assets(
		PlutusScript.create("46010000222499".hex_decode()), 
		[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
		VoidData.new().to_data()
	)
	var result := await tx.complete()

	if result.is_ok():
		result.value.sign(password_input.text)
		var submit_result := await result.value.submit()
		if submit_result.is_err():
			push_error(submit_result.error)
	else:
		push_error(result.error)

func set_wallet(key_ring: SingleAddressWallet):
	if wallet != null:
		remove_child(wallet)
		remove_child(cardano)
		
	wallet = Wallet.MnemonicWallet.new(key_ring, provider)
	add_child(wallet)
	correct_password = password_input.text
	password_warning.text = ""
	cardano = Cardano.new(wallet, provider)
	add_child(cardano)
	_on_wallet_set()
	
# Asynchronously load the wallet from a seedphrase
func _create_wallet_from_seedphrase(seedphrase: String) -> void:
	var old_text := set_button.text
	set_button.text = "Loading wallet..."
	set_button.disabled = true
	generate_button.disabled = true
	var res := await loader.import_from_seedphrase(
		seedphrase,
		"",
		password_input.text,
		0,
		"First account",
		"The first account created")
	if res.is_ok():
		set_wallet(res.value.wallet)
	else:
		push_error("Could not set wallet, found error", res.error)
	set_button.text = old_text
	set_button.disabled = false
	generate_button.disabled = false

func _on_create_script_output_pressed():
	var tx := cardano.new_tx()
	if tx.is_err():
		push_error("could not create tx_builder", tx.error)
		return
		
	var script_address = provider.make_address(Credential.from_script(test_spend_script))

	tx.value.pay_to_address_with_datum_hash(
		script_address,
		BigInt.from_int(5_000_000),
		MultiAsset.empty(),
		BigInt.from_int(66)
	)
	var result : TxBuilder.CompleteResult = await tx.value.complete()

	if result.is_err():
		print("Could not complete transaction", result.error)
		return

	if result.is_ok():
		result.value.sign(password_input.text)
		var hash := await result.value.submit()
		print("Transaction hash:", hash.value.to_hex())

func _on_consume_script_input_pressed():
	var script_address = provider.make_address(Credential.from_script(test_spend_script))
	var utxos := await provider._get_utxos_at_address(script_address)
	var utxos_filtered = utxos.filter(func(u: Utxo): return u.datum_info().has_datum())

	var tx_result := cardano.new_tx()
	if tx_result.is_err():
		push_error("could not create tx_builder", tx_result.error)
		return

	var tx = tx_result.value
	tx.collect_from_script(
		PlutusScriptSource.from_script(test_spend_script),
		utxos_filtered,
		BigInt.from_int(0)
	)
	var result : TxBuilder.CompleteResult = await tx.complete()

	if result.is_err():
		print("Could not complete transaction", result.error)
		return 

	if result.is_ok():
		result.value.sign(password_input.text)
		var hash := await result.value.submit()
		print("Transaction hash:", hash.value.to_hex())


func _on_password_input_text_changed(new_text: String) -> void:
	if wallet != null and new_text != correct_password:
		password_warning.text = "Password incorrect, transaction signing will fail"
	else:
		password_warning.text = ""
