extends RefCounted
class_name AssetName

## The name of an asset. Also known as token name.
##
## An [AssetName] (or token name) identifies a particular asset from any other
## that has the same [PolicyId] (or currency symbol).

var _asset_name: _AssetName

enum Status { SUCCESS = 0, COULD_NOT_DECODE_HEX = 1 }

func _init(asset_name: _AssetName):
	_asset_name = asset_name

## Result of [method from_hex]. If the operation succeeds, [member value] will
## contain a valid [AssetName].
class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: AssetName:
		get: return AssetName.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
class FromBytesResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: AssetName:
		get: return AssetName.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Try to parse an [class AssetName] from [param hash] containing its hex encoding.
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_AssetName._from_hex(hash))

## Try to parse an [AssetName] from a [PackedByteArray].
static func from_bytes(bytes: PackedByteArray) -> FromBytesResult:
	return FromBytesResult.new(_AssetName._from_bytes(bytes))

func to_bytes() -> PackedByteArray:
	return _asset_name.to_bytes()

## Get the hex encoding of the [AssetName].
func to_hex() -> String:
	return _asset_name.to_hex()

func _to_string() -> String:
	return to_hex()
