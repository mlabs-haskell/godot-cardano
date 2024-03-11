extends RefCounted

## You should create a [SingleAddressWallet] with [SingleAddressWalletStore],
## by calling [SingleAddressWalletStore.get_wallet]. Do not use
## [SingleAddressWallet.new]

class_name SingleAddressWallet

enum Status {
	SUCCESS = 0,
	DECRYPTION_ERROR = 1,
	BAD_DECRYPTED_KEY = 2,
	BECH32_ERROR = 3,
	NON_EXISTENT_ACCOUNT = 4
}
var _wallet_loader: SingleAddressWalletLoader
var _wallet : _SingleAddressWallet

func _init(wallet: _SingleAddressWallet, wallet_loader: SingleAddressWalletLoader) -> void:
	self._wallet = wallet
	self._wallet_loader = wallet_loader
	
## Get the account's [Address]
func get_address() -> Address:
	return Address.new(_wallet._get_address())

## Get the account's address as a BECH32-encoded [String].
func get_address_bech32() -> String:
	return _wallet._get_address_bech32()
	
class SingleAddressWalletError extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Signature:
		get: return _res.unsafe_value() as Signature
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
	
	
## Sign the given [Transaction] and obtain a [Signature]
func _sign_transaction(password: String, tx: Transaction) -> SingleAddressWalletError:
	return SingleAddressWalletError.new(
		_wallet._sign_transaction(password.to_utf8_buffer(), tx._tx)
	)

## Adds an account to this wallet's store with the given index
func add_account(account_index: int, password: String):
	_wallet_loader.add_account(account_index, password)
	var get_wallet_result = _wallet_loader.get_wallet(account_index)
	if get_wallet_result.is_err():
		push_error("Could not add account")
	_wallet = get_wallet_result.value._wallet

## Switch to the account with the given `account_index`. It may fail if no such account
## exists. It returns the account index when it succeeds.
func switch_account(account_index: int) -> SingleAddressWalletError:
	return SingleAddressWalletError.new(_wallet._switch_account(account_index))
