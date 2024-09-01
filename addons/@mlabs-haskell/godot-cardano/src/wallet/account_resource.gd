extends Resource
class_name AccountResource

## Storage class for accounts
##
## This is a storage class used in [method SingleAddressWalletLoader.export].

@export
var index: int
@export
var name: String
@export
var description: String
@export
var public_key: PackedByteArray
