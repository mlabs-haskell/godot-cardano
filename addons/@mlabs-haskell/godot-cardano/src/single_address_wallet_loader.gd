extends Node

class_name SingleAddressWalletLoader

enum Status {
	SUCCESS = 0,
	BAD_PHRASE = 1,
	BIP32_ERROR = 2,
	PKCS5_ERROR = 3,
	BAD_SCRYPT_PARAMS = 4,
	COULD_NOT_PARSE_AES_IV = 5,
	ACCOUNT_NOT_FOUND = 6
}

## Emitted when [method SingleAddressWalletStore.import_from_seedphrase]
## returns a result.
signal import_completed(res: WalletImportResult)

## May be null if no wallet was loaded
var _wallet_store : _SingleAddressWalletStore

var _network: Provider.Network

# Used when importing
var thread: Thread

func _init(
	network: Provider.Network,
	wallet_store: _SingleAddressWalletStore = null,
) -> void:
	_wallet_store = wallet_store
	_network = network
	pass

class GetWalletError extends Result:
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
		
## Obtain a [SingleAddressWallet] that can be used for signing transactions.
## The operation may fail in different ways if the store is malformed.
func get_wallet(account_index: int) -> GetWalletError:
	var get_wallet_result = _wallet_store._get_wallet(
		account_index,
		1 if _network == Provider.Network.MAINNET else 0
	)
	return GetWalletError.new(self, get_wallet_result)

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
		_loader._wallet_store = _import_res.wallet_store

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

## Construct a [SingleAddressWalletStoreError] from a mnemonic [param phrase].
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
## This function is asynchronous. You can await it or use hook a callback to
## [signal SingleAddressWalletStore.import_completed].
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
			_SingleAddressWalletStore._import_from_seedphrase(
				phrase,
				phrase_password.to_utf8_buffer(),
				wallet_password.to_utf8_buffer(),
				account_index,
				name,
				account_description,
				1 if _network == Provider.Network.MAINNET else 0))
		call_deferred("emit_signal", "import_completed", res)
			
class WalletCreation extends RefCounted:
	var _create_res: _SingleAddressWalletCreateResult
	var _network: Provider.Network
	var wallet: SingleAddressWallet:
		get: return SingleAddressWallet.new(
			_create_res.wallet,
			SingleAddressWalletLoader.new(_network, _create_res.wallet_store)
		)
	var seed_phrase: String:
		get: return _create_res.seed_phrase
	
	func _init(create_res: _SingleAddressWalletCreateResult, network: Provider.Network):
		_create_res = create_res
		_network = network
			
class WalletCreationResult extends Result:
	var _network: Provider.Network
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: WalletCreation:
		get: return WalletCreation.new(_res.unsafe_value() as _SingleAddressWalletCreateResult, _network)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(network: Provider.Network, res: _Result):
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
	network: Provider.Network) -> WalletCreationResult:
	return WalletCreationResult.new(
		network,
		_SingleAddressWalletStore._create(
			wallet_password.to_utf8_buffer(),
			account_index,
			name,
			account_description,
			1 if network == Provider.Network.MAINNET else 0
		)
	)

func _exit_tree():
	if not (thread == null) and thread.is_started():
		thread.wait_to_finish()
	else:
		pass # the thread was never started or it's still running
		
func add_account(account_index: int, password: String):
	_wallet_store._add_account(account_index, "", "", password.to_utf8_buffer())
