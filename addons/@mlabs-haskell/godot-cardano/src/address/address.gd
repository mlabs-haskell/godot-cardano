extends RefCounted
class_name Address

## A Cardano address
##
## This class represents a Cardano address consisting of a payment [Credential]
## and a (optional) staking [Credential].

var _address: _Address

enum Status { SUCCESS = 0, BECH32_ERROR = 1 }

func _init(address: _Address):
	_address = address

## NOTE: Not currently used.
class ToBech32Result extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: String:
		get: return _res.unsafe_value()
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
	
## Result of [from_bech32]. If the operation succeeds, [member value] contains
## a valid [Address].
class FromBech32Result extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Address:
		get: return Address.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
## Try to parse a BECH32 [String] into an [Address].
static func from_bech32(bech32: String) -> FromBech32Result:
	return FromBech32Result.new(_Address._from_bech32(bech32))

# TODO: We should use the safe ToBech32Result wrapper.
## Convert to a BECH32 [String]. This operation may fail and return an empty
## [String].
func to_bech32() -> String:
	var result = ToBech32Result.new(_address._to_bech32())
	match result.tag():
		Status.SUCCESS:
			return result.value
		_:
			push_error("An error was found while encoding an address as bech32", result.error)
			return ""
			
func to_hex() -> String:
	return _address._to_hex()

func _to_string() -> String:
	return to_bech32()
	
# TODO: Maybe we should use Provider.Network here.
## Construct an [Address] by providing the [param network_id] and payment and
## staking credentials. The latter are optional, [b]but strongly encouraged[/b].
static func build(
	network: ProviderApi.Network,
	payment_cred: Credential,
	stake_cred: Credential = null
) -> Address:
	return new(
		_Address.build(
			1 if network == ProviderApi.Network.MAINNET else 0,
			payment_cred._credential,
			stake_cred._credential if stake_cred else null
		)
	)

func payment_credential() -> Credential:
	return Credential.new(_address.payment_credential())
	
func stake_credential() -> Credential:
	return Credential.new(_address.stake_credential())
