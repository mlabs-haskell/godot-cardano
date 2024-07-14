## A [class Account] is an independent public key derived from the same
## wallet, and hence it has its own [member Account.index],
## [member Account.address_bech32], etc.
##
## Do not construct this class manually. Accounts are created and handled
## automatically by [class SingleAddressWalletLoader].
class_name Account

var _account : _Account

func _init(account: _Account) -> void:
	_account = account
