extends RefCounted
class_name Account

## An account inside a wallet.
##
## An [Account] is an independent public key derived from a
## [SingleAddressWallet], hence it has its own [member Account.index],
## [member Account.address_bech32], etc.
##
## [b]Do not construct this class manually[/b]. Accounts are created and handled
## automatically by [SingleAddressWalletLoader].

#TODO: We should provide access to most (if not all) properties under _Account.
var _account : _Account

func _init(account: _Account) -> void:
	_account = account
