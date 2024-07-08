extends RefCounted
## A Cardano credential
##
## Cardano credentials are used to restrict certain operations, generally UTxO
## spending, but also staking. A credential can be made from:[br][br]
## * A [PubKeyHash]. Access is restricted only to agents that have
##   access to the private key that matches the pub key from which the hash wa
##   generated.
## * Or a [PlutusScript]. Access logic is encoded by the provided script, which
##   can in turn be quite complex.
class_name Credential

var _credential: _Credential = null

func _init(credential: _Credential):
	_credential = credential

## Create a credential from the provided [param script].
static func from_script(script: PlutusScript) -> Credential:
	return new(_Credential.from_script_hash(script.hash()))
	
## Create a credential from the provided [param key_hash].
static func from_key_hash(key_hash: PubKeyHash) -> Credential:
	return new(_Credential.from_key_hash(key_hash._pub_key_hash))
