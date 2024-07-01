extends Resource

class_name SingleAddressWalletResource

@export
var encrypted_master_private_key: PackedByteArray
@export
var accounts: Array[AccountResource]
@export
var scrypt_log_n: int
@export
var scrypt_r: int
@export
var scrypt_p: int
@export
var aes_iv: PackedByteArray
@export
var salt: PackedByteArray
