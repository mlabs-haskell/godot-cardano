extends RefCounted
class_name SingleAddressWallet

## A class for offline wallet operations
##
## This class holds the [b]encrypted[/b] master private key of a user's wallet.
## It can be used for offline wallet operations and queries, such as signing,
## adding accounts and consulting addresses.
##
## You should create a [SingleAddressWallet] with [SingleAddressWalletLoader],
## by calling any of its creation or import methods.
##
## Refer to [OnlineWallet] for a class that has network connectivity and can
## do blockchain queries. In general, this class is the one you are interested
## in for dApp development.

enum Status {
	SUCCESS = 0,
	DECRYPTION_ERROR = 1,
	BAD_DECRYPTED_KEY = 2,
	BECH32_ERROR = 3,
	NON_EXISTENT_ACCOUNT = 4
}
var _wallet_loader: SingleAddressWalletLoader
var _wallet : _SingleAddressWallet

## WARNING: Do not use this constructor! Use any of the import/creation methods
## exposed in [SingleAddressWalletLoader].
func _init(wallet: _SingleAddressWallet, wallet_loader: SingleAddressWalletLoader) -> void:
	self._wallet = wallet
	self._wallet_loader = wallet_loader
	
## Get the account's [Address]
func get_address() -> Address:
	return Address.new(_wallet._get_address())

## Get the account's address as a BECH32-encoded [String].
func get_address_bech32() -> String:
	return _wallet.get_address_bech32()
	
func get_address_hex() -> String:
	return get_address().to_hex()

## Sign the given [Transaction] and obtain a [Signature]
func sign_transaction(password: String, tx: Transaction) -> OnlineWallet.SignTxResult:
	return OnlineWallet.SignTxResult.new(
		_wallet._sign_transaction(password.to_utf8_buffer(), tx._tx)
	)

class SignDataResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: DataSignature:
		get: return _res.unsafe_value() as DataSignature
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Sign the given [String] representing hex encoded payload and obtain a [DataSignature]
func sign_data(password: String, data: String) -> SignDataResult:
	return SignDataResult.new(
		_wallet._sign_data(password.to_utf8_buffer(), data.hex_decode())
	)

## Adds an account to this wallet with the given index
func add_account(account_index: int, password: String) -> SingleAddressWallet.AddAccountResult:
	var res: _Result = _wallet_loader._add_account(account_index, password)
	return AddAccountResult.new(res)
	
## Result of calling [method add_account]. If the operation succeeds,
## [member value] will contain
class AddAccountResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Account:
		get: return Account.new(_res.unsafe_value() as _Account)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Switch to the account with the given `account_index`. It may fail if no such account
## exists. It returns the account index when it succeeds.
func switch_account(account: Account) -> int:
	return _wallet.switch_account(account._account)
	
## Return a list of accounts currently available in the wallet
func accounts() -> Array[Account]:
	var accounts : Array[Account] = []
	var _accounts: Array[_Account] = self._wallet_loader._wallet_loader.get_accounts()
	for a in _accounts:
		accounts.push_back(Account.new(a))
	return accounts
	
## Export wallet to a resource.
func export() -> SingleAddressWalletResource:
	return _wallet_loader.export()
