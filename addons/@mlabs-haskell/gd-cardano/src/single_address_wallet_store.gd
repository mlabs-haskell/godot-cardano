extends Resource

class_name SingleAddressWalletStore

enum Status {
	SUCCESS = 0,
	BAD_PHRASE = 1,
	BIP32_ERROR = 2,
	PKCS5_ERROR = 3,
	BAD_SCRYPT_PARAMS = 4,
	COULD_NOT_PARSE_AES_IV = 5,
	ACCOUNT_NOT_FOUND = 6
}

var _wallet_store : _SingleAddressWalletStore

func _init(wallet_store: _SingleAddressWalletStore) -> void:
	self._wallet_store = wallet_store


class GetWalletError extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: SingleAddressWallet:
		get: return SingleAddressWallet.new(_res.unsafe_value() as _SingleAddressWallet)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
## Obtain a [SingleAddressWallet] that can be used for signing transactions.
## The operation may fail in different ways if the store is malformed.
func get_wallet(account_index: int) -> GetWalletError:
	return GetWalletError.new(_wallet_store._get_wallet(account_index))

class ImportResult extends RefCounted:
	var _import_res: _SingleAddressWalletImportResult
	var wallet_store: SingleAddressWalletStore:
		get: return SingleAddressWalletStore.new(_import_res.wallet_store)
	var wallet: SingleAddressWallet:
		get: return SingleAddressWallet.new(_import_res.wallet)
	
	func _init(import_res: _SingleAddressWalletImportResult):
		_import_res = import_res

class ImportWalletError extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: ImportResult:
		get: return ImportResult.new(_res.unsafe_value() as _SingleAddressWalletImportResult)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Construct a [SingleAddressWalletStoreError] from a mnemonic [phrase].
## 
## The phrase should follow the BIP32 standard and it may have a [phrase_password]
## (if not, an empty string should be passed). This standard is followed by
## almost all Cardano light wallets, so importing an already existing wallet
## is normallly achieved by calling this method with the wallet's seed phrase
## and an empty password.
##
## This function also assings a [wallet_password] to the wallet that must be
## inputted for any method that requires it (such as signing or adding new accounts).
##
## Optionally, an [account_index], [name] and [account_description] may be passed. By default, the
## account index is set to 0, with all subsequent accounts added to the wallet taking the next
## indices.
static func import_from_seedphrase(
	phrase: String,
	phrase_password: String, 
	wallet_password: String,
	account_index: int,
	name: String,
	account_description: String) -> ImportWalletError:
	return ImportWalletError.new(
		_SingleAddressWalletStore._import_from_seedphrase(
			phrase, phrase_password, wallet_password, account_index, name, account_description))