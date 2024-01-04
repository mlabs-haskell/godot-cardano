extends RefCounted

## You should not create a [PrivateKeyAccount] with [PrivateKeyAccount.new],
## instead you should use [PrivateKeyAccount.create].

class_name PrivateKeyAccount

enum Status { SUCCESS = 0, BAD_PHRASE = 1, BECH32_ERROR = 2 }

var _account : _PrivateKeyAccount

func _init(account: _PrivateKeyAccount) -> void:
	self._account = account

class FromMnemonicResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PrivateKeyAccount:
		get: return PrivateKeyAccount.new(_res.unsafe_value() as _PrivateKeyAccount)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Construct a [PrivateKeyAccount] from a mnemonic [param phrase]. The phrase should follow the
## BIP32 standard.
static func from_mnemonic(phrase: String) -> FromMnemonicResult:
	return FromMnemonicResult.new(_PrivateKeyAccount._from_mnemonic(phrase))
	
class GetAddressResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: String:
		get: return _res.unsafe_value()
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
	
## Get the account's address as a BECH32-encoded [String].
func get_address_bech32() -> GetAddressResult:
	return GetAddressResult.new(_account._get_address_bech32())
	
## Sign the given [Transaction] and obtain a [Signature]
func sign_transaction(tx: Transaction) -> Signature:
	return _account._sign_transaction(tx._tx)
