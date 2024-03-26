extends GutTest

func test_assert_bigint_eq() -> void:
	var bigint_result := BigInt.from_str("1")
	assert_true(
		bigint_result.is_ok() and bigint_result.value.eq(BigInt.one()),
		"BigInt.from_int(1) should equal Bigint.one()"
	)

class TestWallets extends GutTest:
	var _wallets: Array
	
	func before_all() -> void:
		assert(FileAccess.file_exists("res://test_data.json"))
		var data_json := FileAccess.get_file_as_string("res://test_data.json")
		var data: Dictionary = JSON.parse_string(data_json)
		_wallets = data.wallets
	
	func test_create_and_import(
		account_index: int = use_parameters([0,12])
	) -> void:
		var loader := SingleAddressWalletLoader.new()
		var create_result := loader.create(
			"1234",
			account_index,
			"",
			""
		)
		assert_true(
			create_result.is_ok(),
			"Create new wallet with account %d" % account_index
		)
		
		var import_result := await loader.import_from_seedphrase(
			create_result.value.seed_phrase,
			"",
			"1234",
			account_index,
			"",
			""
		)
		assert_true(
			import_result.is_ok(),
			"Import created wallet with account %d" % account_index
		)
		
		var wallet := Wallet.MnemonicWallet.new(
			import_result.value.wallet,
			null,
			false
		)
		wallet.add_account(account_index, "1234")
		assert_eq(
			create_result.value.wallet.get_address_bech32(),
			wallet._get_change_address().to_bech32()
		)
		
	func test_wallet_import() -> void:
		var loader := SingleAddressWalletLoader.new()
		for wallet_data: Dictionary in _wallets:
			var seed_phrase: String = wallet_data['seedPhrase']
			var import_result := await loader.import_from_seedphrase(
				seed_phrase,
				"",
				"1234",
				0,
				"",
				""
			)
			assert_true(
				import_result.is_ok(),
				"Import wallet from seed phrase"
			)
			
			for account_data: Dictionary in wallet_data['accounts']:
				var wallet := Wallet.MnemonicWallet.new(
					import_result.value.wallet,
					null,
					false
				)
				var index: int = account_data['index']
				var address: String = account_data['address']
				wallet.add_account(index, "1234")
				wallet.switch_account(index)
				
				assert_eq(address, wallet._get_change_address().to_bech32())

class TestSdk extends GutTest:
	var blockfrost_tests := [blockfrost_payment, blockfrost_mint]
	var _funding_address: Address
	var _provider: Provider
	var _wallets: Array[Wallet.MnemonicWallet] = []
	
	func or_quit(test: bool, msg: String = "") -> void:
		if not test:
			push_error(msg)
			get_tree().quit(1)
		
	func load_funding_wallet() -> SingleAddressWallet:
		var funding_wallet_phrase := OS.get_environment("TESTNET_SEED_PHRASE")
		if funding_wallet_phrase == "":
			or_quit(
				FileAccess.file_exists("res://seed_phrase.txt"),
				"No funding wallet available"
			)
			funding_wallet_phrase = FileAccess.get_file_as_string("res://seed_phrase.txt")
		var loader = SingleAddressWalletLoader.new()
		var import_result := await loader.import_from_seedphrase(
			funding_wallet_phrase,
			"",
			"1234",
			0,
			"",
			""
		)
		or_quit(
			import_result.is_ok(),
			"Import funding wallet"
		)
		return import_result.value.wallet

	func tx_with(
		cardano: Cardano,
		build: Callable,
		name: String = "test"
	) -> TransactionHash:
		var create_tx_result := cardano.new_tx()
		assert_true(create_tx_result.is_ok(), "Create %s tx" % name)
		if create_tx_result.is_ok():
			var tx := create_tx_result.value
			build.call(tx)
			var complete_tx_result := tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build %s tx" % name)
			if complete_tx_result.is_ok():
				complete_tx_result.value.sign("1234")
				var submit_result := await complete_tx_result.value.submit()
				assert(submit_result.is_ok())
				var tx_hash := submit_result.value
				assert(tx_hash != null)
				return tx_hash
			else:
				gut.p(complete_tx_result.error)
		else:
			gut.p('Failed to create transaction: %s' % create_tx_result.error)
		return null

	func init_blockfrost_tests() -> void:
		or_quit(FileAccess.file_exists("res://preview_token.txt"), "No Blockfrost token available")
		var preview_token := FileAccess.get_file_as_string("res://preview_token.txt").strip_edges()
		var funding_wallet := await load_funding_wallet()
		
		_provider = BlockfrostProvider.new(
			Provider.Network.PREVIEW,
			preview_token,
		)
		add_child(_provider)
		var wallet := Wallet.MnemonicWallet.new(funding_wallet, _provider)
		_funding_address = wallet._get_change_address()
		add_child(wallet)
		var cardano := Cardano.new(wallet, _provider)
		add_child(cardano)
		
		await _provider.got_protocol_parameters
		
		for _t: Callable in blockfrost_tests:
			var create_result := SingleAddressWalletLoader.create(
				"1234",
				0,
				"",
				""
			)
			assert_true(create_result.is_ok(), "Create new wallet")
			var new_wallet := Wallet.MnemonicWallet.new(
				create_result.value.wallet,
				_provider
			)
			_wallets.push_back(new_wallet)
					
			# backup the seed phrase in case of an early exit
			var file = FileAccess.open(
				"user://%s" % new_wallet._get_change_address().to_bech32(),
				FileAccess.WRITE
			)
			file.store_string(create_result.value.seed_phrase + "\n")
			file.close()

		var utxos := await wallet._get_updated_utxos()
		var fund_tx_hash := await tx_with(
			cardano,
			func (tx: TxBuilder) -> void:
				for test_wallet in _wallets:
					tx.pay_to_address(
						test_wallet._get_change_address(),
						BigInt.from_int(10_000_000),
						MultiAsset.empty()
					),
			"test wallet funding"
		)
		assert(fund_tx_hash != null)
		await _provider.await_utxos_at(wallet._get_change_address(), fund_tx_hash)
		gut.p('Transaction confirmed')
		remove_child(wallet)
		remove_child(cardano)
		
	func test_invalid_signature() -> void:
		or_quit(FileAccess.file_exists("res://preview_token.txt"), "No Blockfrost token available")
		var preview_token := FileAccess.get_file_as_string("res://preview_token.txt").strip_edges()
		var funding_wallet := await load_funding_wallet()
		
		_provider = BlockfrostProvider.new(
			Provider.Network.PREVIEW,
			preview_token,
		)
		add_child(_provider)
		var wallet := Wallet.MnemonicWallet.new(funding_wallet, _provider)
		_funding_address = wallet._get_change_address()
		add_child(wallet)
		var cardano := Cardano.new(wallet, _provider)
		add_child(cardano)
		
		await _provider.got_protocol_parameters
		await wallet._get_updated_utxos()
		var create_tx_result := cardano.new_tx()
		assert_true(create_tx_result.is_ok(), "Create test wallet funding tx")
		if create_tx_result.is_ok():
			var fund_tx := create_tx_result.value
			var complete_tx_result := fund_tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build test wallet funding tx")
			if complete_tx_result.is_ok():
				var complete_tx := complete_tx_result.value
				complete_tx.sign("12345")
				assert_eq(
					complete_tx._results[0].tag(),
					TxComplete.TxCompleteStatus.INVALID_SIGNATURE,
					"Signing transaction with incorrect password fails"
				)
		else:
			print("Failed to create transaction: %s" % create_tx_result.error)
		remove_child(wallet)
		remove_child(cardano)
			
	func blockfrost_mint(cardano: Cardano) -> TransactionHash:
		return await tx_with(
			cardano,
			func(tx: TxBuilder) -> void:	
				tx.mint_assets(
					PlutusScript.create("46010000222499".hex_decode()), 
					[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
					VoidData.new()
				),
			"token minting"
		)

	func blockfrost_payment(cardano: Cardano) -> TransactionHash:
		return await tx_with(
			cardano,
			func(_tx: TxBuilder) -> void: pass,
			"redundant payment"
		)

	func test_blockfrost(test: Callable = use_parameters(blockfrost_tests)) -> void:
		await init_blockfrost_tests()
		
		var wallet := _wallets[blockfrost_tests.find(test)]
		var cardano := Cardano.new(wallet, _provider)
		add_child(wallet)
		add_child(cardano)
		await _provider.got_protocol_parameters
		await wallet.update_utxos()
		var final_tx_hash: TransactionHash = await test.call(cardano)
		await _provider.await_utxos_at(wallet._get_change_address(), final_tx_hash)
		var utxos := await wallet._get_updated_utxos()
		tx_with(
			cardano,
			func (tx: TxBuilder) -> void:
				tx.collect_from(utxos)
				tx.set_change_address(_funding_address),
			"funding return"
		)
		remove_child(wallet)
		remove_child(cardano)
