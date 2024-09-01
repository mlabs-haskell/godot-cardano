extends RefCounted
class_name SingleAddressWalletLoader

## A utility class used for loading/creating wallets
##
## This class is provided for the safe construction, import and export of
## [SingleAddressWallet]s. Because of this, it should only be used once and then
## discarded.

enum Status {
	SUCCESS = 0,
	BAD_PHRASE = 1,
	BIP32_ERROR = 2,
	PKCS5_ERROR = 3,
	BAD_SCRYPT_PARAMS = 4,
	COULD_NOT_PARSE_AES_IV = 5,
	ACCOUNT_NOT_FOUND = 6,
	ATTRIBUTE_NOT_FOUND_IN_RESOURCE = 7,
	ATTRIBUTE_WITH_WRONG_TYPE_IN_RESOURCE = 8,
	NO_ACCOUNTS_IN_WALLET = 9,
}

## Emitted when [method SingleAddressWalletStore.import_from_seedphrase]
## returns a result.
signal import_completed(res: WalletImportResult)

# May be null if no wallet was loaded
var _wallet_loader : _SingleAddressWalletLoader

var _network: ProviderApi.Network

# Used when importing
var thread: Thread

## Only construct a [SingleAddressWalletLoader] if you plan to use a non-static
## method for obtaining a [SingleAddressWallet].
func _init(
	network: ProviderApi.Network,
	wallet_loader: _SingleAddressWalletLoader = null,
) -> void:
	_wallet_loader = wallet_loader
	_network = network
	pass

class GetWalletResult extends Result:
	var _wallet_loader : SingleAddressWalletLoader
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: SingleAddressWallet:
		get: return SingleAddressWallet.new(_res.unsafe_value() as _SingleAddressWallet, _wallet_loader)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

	func _init(wallet_loader: SingleAddressWalletLoader, res: _Result):
		super(res)
		_wallet_loader = wallet_loader

class WalletImport extends RefCounted:
	var _import_res: _SingleAddressWalletImportResult
	var _loader: SingleAddressWalletLoader
	var wallet: SingleAddressWallet:
		get: return SingleAddressWallet.new(
			_import_res.wallet,
			_loader
		)
	
	func _init(import_res: _SingleAddressWalletImportResult, loader: SingleAddressWalletLoader):
		_import_res = import_res
		_loader = loader
		_loader._wallet_loader = _import_res.wallet_loader

class WalletImportResult extends Result:
	var _loader: SingleAddressWalletLoader
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: WalletImport:
		get: return WalletImport.new(
			_res.unsafe_value() as _SingleAddressWalletImportResult,
			_loader
		)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(loader: SingleAddressWalletLoader, res: _Result):
		super(res)
		_loader = loader

## Construct a [WalletImportResult] from a mnemonic [param phrase].
## 
## The phrase should follow the BIP32 standard and it may have a [phrase_password]
## (if not, an empty string should be passed). This standard is followed by
## almost all Cardano light wallets, so importing an already existing wallet
## is normally achieved by calling this method with the wallet's seed phrase
## and an empty password.
##
## This function also assigns a [param wallet_password] to the wallet that must be
## entered for any method that requires it (such as signing or adding new accounts).
##
## Optionally, a [param account_index], [param name] and
## [param account_description] may be passed. By default, the account index is
## set to 0, with all subsequent accounts added to the wallet taking the next
## indices.
##
## This function is asynchronous. You can await it or connect a callback to
## [signal SingleAddressWalletLoader.import_completed].
func import_from_seedphrase(
	phrase: String,
	phrase_password: String, 
	wallet_password: String,
	account_index: int,
	name: String,
	account_description: String) -> WalletImportResult:
		if not (thread == null):
			if thread.is_alive():
				push_warning("Import in progress, ignoring latest call...")
				var old_res: WalletImportResult = await(import_completed)
				return old_res
			elif thread.is_started():
				thread.wait_to_finish() # the thread should have stopped working by now
			else:
				push_warning("thread object is initialized but not started")
		thread = Thread.new()
		thread.start(
			_wrap_import_from_seedphrase.bind(
				phrase, phrase_password, wallet_password, account_index, name, account_description
			)
		)
		var res: WalletImportResult = await import_completed
		thread.wait_to_finish()
		return res

# TODO: docs if we won't figure out hpw to do it with threads	
func import_from_seedphrase_wo_new_thread(
	phrase: String,
	phrase_password: String, 
	wallet_password: String,
	account_index: int,
	name: String,
	account_description: String) -> WalletImportResult:
		_wrap_import_from_seedphrase(
				phrase, phrase_password, wallet_password, account_index, name, account_description
			)
		var res: WalletImportResult = await import_completed
		return res

## Import from a [class SingleAddressWalletResource]. If the resource is
## malformed, an error will be thrown. To export a wallet, read
## [method SingleAddressWalletLoader.export].
##
## This function is asynchronous. You can await it or connect a callback to
## [signal SingleAddressWalletLoader.import_completed].
func import_from_resource(resource: SingleAddressWalletResource) -> WalletImportResult:
		if not (thread == null):
			if thread.is_alive():
				push_warning("Import in progress, ignoring latest call...")
				var old_res: WalletImportResult = await(import_completed)
				return old_res
			elif thread.is_started():
				thread.wait_to_finish() # the thread should have stopped working by now
			else:
				push_warning("thread object is initialized but not started")
		thread = Thread.new()
		thread.start(
			_wrap_import_from_resource.bind(
				resource
			)
		)
		var res: WalletImportResult = await import_completed
		thread.wait_to_finish()
		return res
		
## Export the wallet to a [class SingleAddressWalletResource], which can
## subsequently used like any other Godot [class Resource].
##
## For importing, read [method SingleAddressWalletLoader.import_from_resource].
##
## This function will return null if no wallet has been loaded or created so far.
func export() -> SingleAddressWalletResource:
	if _wallet_loader == null:
		push_error("No wallet has been loaded")
		return null
	var res := SingleAddressWalletResource.new()
	var dict := _wallet_loader.export_to_dict()
	for account: Dictionary in dict["accounts"]:
		var account_res = AccountResource.new()
		account_res.index = account.index
		account_res.name = account.name
		account_res.description = account.description
		account_res.public_key = account.public_key
		res.accounts.push_back(account_res)
	res.encrypted_master_private_key = dict["encrypted_master_private_key"]
	res.salt = dict["salt"]
	res.scrypt_log_n = dict["scrypt_log_n"]
	res.scrypt_r = dict["scrypt_r"]
	res.scrypt_p = dict["scrypt_p"]
	res.aes_iv = dict["aes_iv"]
	return res
			
func _wrap_import_from_seedphrase(
	phrase: String,
	phrase_password: String, 
	wallet_password: String,
	account_index: int,
	name: String,
	account_description: String) -> void:
		var res := WalletImportResult.new(
			SingleAddressWalletLoader.new(_network),
			_SingleAddressWalletLoader._import_from_seedphrase(
				phrase,
				phrase_password.to_utf8_buffer(),
				wallet_password.to_utf8_buffer(),
				account_index,
				name,
				account_description,
				1 if _network == ProviderApi.Network.MAINNET else 0))
		call_deferred("emit_signal", "import_completed", res)
		
func _wrap_import_from_resource(resource: SingleAddressWalletResource) -> void:
		var res := WalletImportResult.new(
			SingleAddressWalletLoader.new(_network),
			_SingleAddressWalletLoader._import_from_resource(
				resource,
				1 if _network == ProviderApi.Network.MAINNET else 0))
		call_deferred("emit_signal", "import_completed", res)
			
## The output of creating a wallet. It consists of a [member WalletCreation.seed_phrase] and a
## [member WalletCreation.wallet] that can be used 
class WalletCreation extends RefCounted:
	var _create_res: _SingleAddressWalletCreateResult
	var _network: ProviderApi.Network
	var wallet: SingleAddressWallet:
		get: return SingleAddressWallet.new(
			_create_res.wallet,
			SingleAddressWalletLoader.new(_network, _create_res.wallet_loader)
		)
	var seed_phrase: String:
		get: return _create_res.seed_phrase
	
	func _init(create_res: _SingleAddressWalletCreateResult, network: ProviderApi.Network):
		_create_res = create_res
		_network = network
			
class WalletCreationResult extends Result:
	var _network: ProviderApi.Network
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: WalletCreation:
		get: return WalletCreation.new(_res.unsafe_value() as _SingleAddressWalletCreateResult, _network)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(network: ProviderApi.Network, res: _Result):
		super(res)
		_network = network

## Construct a [class WalletCreation] from a wallet password and using
## Godot's entropy source.
## Check [SingleAddressWalletStore.import_from_seedphrase] to learn more about
## how Godot wallets work.
static func create(
	wallet_password: String,
	account_index: int,
	name: String,
	account_description,
	network: ProviderApi.Network) -> WalletCreationResult:
	return WalletCreationResult.new(
		network,
		_SingleAddressWalletLoader._create(
			wallet_password.to_utf8_buffer(),
			account_index,
			name,
			account_description,
			1 if network == ProviderApi.Network.MAINNET else 0
		)
	)
		
func _add_account(account_index: int, password: String) -> _Result:
	return _wallet_loader._add_account(account_index, "", "", password.to_utf8_buffer())
