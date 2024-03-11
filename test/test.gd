extends GutTest

func test_assert_bigint_eq():
	var bigint_result = BigInt.from_str("1")
	assert_true(
		bigint_result.is_ok() and bigint_result.value.eq(BigInt.one()),
		"BigInt.from_int(1) should equal Bigint.one()"
	)

class TestWallets extends GutTest:
	var _wallets: Array
	
	func before_all() -> void:
		assert(FileAccess.file_exists("res://test_data.json"))
		var data_json = FileAccess.get_file_as_string("res://test_data.json")
		var data = JSON.parse_string(data_json)
		_wallets = data.wallets
	
	func test_create_and_import(account_index=use_parameters([0,12])):
		var loader = SingleAddressWalletLoader.new()
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
		
	func test_wallet_import():
		var loader = SingleAddressWalletLoader.new()
		for wallet_data: Dictionary in _wallets:
			var import_result := await loader.import_from_seedphrase(
				wallet_data['seedPhrase'],
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
			
			for account_data in wallet_data['accounts']:
				var wallet := Wallet.MnemonicWallet.new(
					import_result.value.wallet,
					null,
					false
				)
				wallet.add_account(account_data['index'], "1234")
				wallet.switch_account(account_data['index'])
				
				assert_eq(
					account_data['address'],
					wallet._get_change_address().to_bech32()
				)

class TestSdk extends GutTest:
	var blockfrost_tests = [blockfrost_payment, blockfrost_mint]
	var _funding_address: Address
	var _provider: Provider
	var _wallets: Array[Wallet.MnemonicWallet] = []
	
	func before_all():
		assert(FileAccess.file_exists("res://preview_token.txt"))
		assert(FileAccess.file_exists("res://seed_phrase.txt"))
		var preview_token = FileAccess.get_file_as_string("res://preview_token.txt").strip_edges()
		var funding_wallet_phrase = FileAccess.get_file_as_string("res://seed_phrase.txt")
		
		_provider = BlockfrostProvider.new(
			Provider.Network.PREVIEW,
			preview_token,
		)
		var loader = SingleAddressWalletLoader.new()
		var import_result := await loader.import_from_seedphrase(
			funding_wallet_phrase,
			"",
			"1234",
			0,
			"",
			""
		)
		add_child(_provider)
		assert_true(import_result.is_ok(), "Import funding wallet")
		var wallet := Wallet.MnemonicWallet.new(
			import_result.value.wallet,
			_provider
		)
		_funding_address = wallet._get_change_address()
		add_child(wallet)
		var cardano := Cardano.new(wallet, _provider)
		add_child(cardano)
		
		await _provider.got_protocol_parameters
		await wallet.got_updated_utxos
		
		for _t in blockfrost_tests:
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

		var create_tx_result := cardano.new_tx()
		assert_true(create_tx_result.is_ok(), "Create test wallet funding tx")
		if create_tx_result.is_ok():
			var fund_tx := create_tx_result.value
			
			for test_wallet in _wallets:
				fund_tx.pay_to_address(
					test_wallet._get_change_address(),
					BigInt.from_int(10_000_000),
					MultiAsset.empty()
				)
				
			wallet.update_utxos()
			await wallet.got_updated_utxos
			var complete_tx_result := fund_tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build test wallet funding tx")
			if complete_tx_result.is_ok():
				complete_tx_result.value.sign("1234")
				var tx_hash := await complete_tx_result.value.submit()
				assert(tx_hash != null)
				await _provider.await_tx(tx_hash)
				gut.p('Transaction confirmed')
		remove_child(wallet)
		remove_child(cardano)
	
	func blockfrost_payment(cardano: Cardano):
		var create_tx_result := cardano.new_tx()
		assert_true(create_tx_result.is_ok(), "Create redundant payment tx")
		await cardano.wallet.update_utxos()
		await cardano.wallet._get_updated_utxos()
		if create_tx_result.is_ok():
			var tx := create_tx_result.value
			var complete_tx_result := tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build redundant payment tx")
			if complete_tx_result.is_ok():
				complete_tx_result.value.sign("1234")
				var tx_hash := await complete_tx_result.value.submit()
				assert(tx_hash != null)
				await _provider.await_tx(tx_hash)
				gut.p('Transaction confirmed')
			else:
				gut.p(complete_tx_result.error)
		else:
			gut.p('Failed to create transaction: %s' % create_tx_result.error)
		
	func blockfrost_mint(cardano: Cardano):
		var create_tx_result := cardano.new_tx()
		assert_true(create_tx_result.is_ok(), "Create token minting tx")
		await cardano.wallet.update_utxos()
		await cardano.wallet._get_updated_utxos()
		if create_tx_result.is_ok():
			var tx := create_tx_result.value	
			tx.mint_assets(
				PlutusScript.create("46010000222499".hex_decode()), 
				[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
				VoidData.new()
			)
			var complete_tx_result := tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build token minting tx")
			if complete_tx_result.is_ok():
				complete_tx_result.value.sign("1234")
				var tx_hash := await complete_tx_result.value.submit()
				assert(tx_hash != null)
				await _provider.await_tx(tx_hash)
				gut.p('Transaction confirmed')
			else:
				gut.p(complete_tx_result.error)
		else:
			gut.p('Failed to create transaction: %s' % create_tx_result.error)
		
	func test_blockfrost(test=use_parameters(blockfrost_tests)):
		var wallet := _wallets[blockfrost_tests.find(test)]
		var cardano := Cardano.new(wallet, _provider)
		add_child(wallet)
		add_child(cardano)
		await _provider.got_protocol_parameters
		await wallet.update_utxos()
		await wallet._get_updated_utxos()
		
		await test.call(cardano)
		
		await wallet.update_utxos()
		var utxos := await wallet._get_updated_utxos()
		var create_tx_result := cardano.new_tx()
		assert_true(create_tx_result.is_ok(), "Create funding return tx")
		if create_tx_result.is_ok():
			var tx := create_tx_result.value
			tx.collect_from(utxos)
			tx.set_change_address(_funding_address)
			var complete_tx_result := tx.complete()
			assert_true(complete_tx_result.is_ok(), "Build funding return tx")
			if complete_tx_result.is_ok():
				complete_tx_result.value.sign("1234")
				await complete_tx_result.value.submit()
				
		remove_child(wallet)
		remove_child(cardano)
