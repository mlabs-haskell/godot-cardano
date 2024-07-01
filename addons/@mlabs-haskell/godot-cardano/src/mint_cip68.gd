@tool
extends Resource

## This resource is used for creating a valid pair of CIP68 _reference_
## and _user_ tokens, as described in the specification:
##
## https://cips.cardano.org/cip/CIP-0068
##
## This class runs assertions in the editor to validate that the provided
## metadata is valid for a CIP68 token.

class_name MintCip68

@export_category("Token Name")
@export
## The token name *body* (i.e: the part of the token name
## that is not the CIP67 header).
var token_name: PackedByteArray:
	set(v):
		token_name = v.slice(0,32)

@export
# FIXME: Currently this doesn't work if you put one character at a time.
var token_name_as_hex: String:
	get:
		return token_name.hex_encode()
	set(v):
		if (v.length() % 2 == 0):
			token_name = v.hex_decode()
		
@export
var token_name_as_utf8: String:
	get:
		return token_name.get_string_from_utf8()
	set(v):
		token_name = v.to_utf8_buffer()

@export_category("CIP25 Metadata")
@export
## The standard "name" field.
var name: String
@export
## The standard "image" field. This should be a valid URI.
var image: String
@export_enum("image/webp", "image/jpeg", "image/gif", "image/png")
## The standard "mediaType" field.
var media_type: String = "image/webp"
@export
## The standard "description" field.
var description: String = ""
@export
## An array of [class FileDetails].
var file_details : Array[FileDetails] = []
@export_category("Additional Metadata")
@export
## This is _non-standard_ CIP-25 metadata.
##
## Use this for any additional fields you want to provide that are not
## required by the CIP25 standard. Any fields overlapping with mandatory field
## names (like "name" and "image") will be ignored.
##
## Keys of the dictionary should be [String]s, while values may be:
## 1. [String] (which will be converted [PackedByteArray])
## 2. [PackedByteArray]
## 3. [int] (which will be converted to [BigInt])
## 4. [BigInt]
## 5. [Array], [b]but only if its elements are valid values[\b].
## 6. [Dictionary], [b]but only if its keys and values are valid[\b].
##
## Notably, you may not use neither [bool] nor [Constr]. If these conditions are
## too restrictive, take a look at [member MintCip68Pair.extra_metadata].
var non_standard_metadata: Dictionary = {}:
	set(v):
		non_standard_metadata = v
		_homogenize_or_fail(non_standard_metadata)
## This corresponds to the third field of the CIP-68 datum. Use this if you need
## to store data in any form that is not compliant with CIP-25. No restrictions
## apply other than the usual ones for encoding a datum.
var extra_plutus_data: PlutusData = VoidData.new().to_data():
	get:
		if FileAccess.file_exists(extra_plutus_data_json_path):
			var json := JSON.parse_string(FileAccess.get_file_as_string(extra_plutus_data_json_path))
			if json != null:
				return PlutusData.from_json(json)
		return extra_plutus_data
	set(v):
		assert(v.serialize().is_ok()
		, "Failed to serialize of extra_plutus_data")
		extra_plutus_data = v
enum ExtraPlutusDataType {
	INT,
	BYTES,
	JSON_FILE,
	JSON_INLINE,
	CBOR_HEX
}

# TODO: Use _set and _get instead of allocating data where possible
@export_category("Extra Plutus Data")
@export
var extra_plutus_data_type: ExtraPlutusDataType = 0:
	set(v):
		extra_plutus_data_type = v
		notify_property_list_changed()
@export
var extra_plutus_data_int: int:
	get:
		if extra_plutus_data is BigInt:
			return extra_plutus_data.to_str().to_int()
		return 0
	set(v):
		extra_plutus_data = BigInt.from_int(v)
		extra_plutus_data_json = JSON.stringify(extra_plutus_data.to_json())
		extra_plutus_data_json_path = ""

@export
var extra_plutus_data_bytes: PackedByteArray:
	get:
		if extra_plutus_data is PlutusBytes:
			return extra_plutus_data.get_data()
		return PackedByteArray()
	set(v):
		extra_plutus_data = PlutusBytes.new(v)
		extra_plutus_data_json = JSON.stringify(extra_plutus_data.to_json())
		extra_plutus_data_json_path = ""

@export
# FIXME: Currently this doesn't work if you put one character at a time.
var extra_plutus_data_as_hex: String:
	get:
		return extra_plutus_data_bytes.hex_encode()
	set(v):
		if (v.length() % 2 == 0):
			extra_plutus_data_bytes = v.hex_decode()
@export
var extra_plutus_data_as_utf8: String:
	get:
		return extra_plutus_data_bytes.get_string_from_utf8()
	set(v):
		extra_plutus_data_bytes = v.to_utf8_buffer()

var extra_plutus_data_cbor: PackedByteArray:
	get:
		var result = extra_plutus_data.serialize()
		if result.is_ok():
			return result.value
		push_error("Failed to serialize PlutusData: %s" % result.error)
		return PackedByteArray()
	set(v):
		var result = PlutusData.deserialize(v)
		if result != null:
			extra_plutus_data = result
			extra_plutus_data_json = JSON.stringify(extra_plutus_data.to_json())
			extra_plutus_data_json_path = ""
@export
# FIXME: Currently this doesn't work if you put one character at a time.
var extra_plutus_data_cbor_hex: String:
	get:
		return extra_plutus_data_cbor.hex_encode()
	set(v):
		if (v.length() % 2 == 0):
			extra_plutus_data_cbor = v.hex_decode()

@export_multiline
var extra_plutus_data_json: String:
	get:
		var json = JSON.new()
		var error = json.parse(extra_plutus_data_json)
		if error != OK:
			return extra_plutus_data_json
		var parsed := PlutusData.from_json(json.data)
		if parsed == null:
			return extra_plutus_data_json
		var from_data = JSON.stringify(extra_plutus_data.to_json(), "  ")
		return from_data
	set(v):
		var json := JSON.parse_string(v)
		extra_plutus_data_json = v
		if json != null:
			var data = PlutusData.from_json(json)
			if data != null:
				extra_plutus_data = data
			else:
				push_error("Failed to parse PlutusData")
		else:
			push_error("Failed to parse JSON")

@export_file("*.json")
var extra_plutus_data_json_path: String = ""
		
@export_category("Minting")
@export
## Whether or not multiple user tokens can be minted. This determines the asset 
## class used as defined in the CIP-68 specifications.
var fungible: bool = false:
	set(v):
		fungible = v
		notify_property_list_changed()
@export
## Initial quantity minted via [method TxBuilder.mint_cip68_pair]. In cases where
## the minting policy is one-shot, this will be the total supply for this token.
var initial_quantity: int = 1:
	get:
		if not fungible:
			return 1
		return initial_quantity
	set(v):
		assert(v == 1 or fungible, "Only fungible tokens can have a non-one quantity")
		initial_quantity = v
		
func get_user_token_name() -> AssetName:
	var user_token_name := "000de140".hex_decode() if not fungible else "0014df10".hex_decode()
	user_token_name.append_array(token_name)
	return AssetName.from_bytes(user_token_name).value
	
func get_ref_token_name() -> AssetName:
	var ref_token_name := "000643b0".hex_decode()
	ref_token_name.append_array(token_name)
	return AssetName.from_bytes(ref_token_name).value

func get_quantity() -> BigInt:
	return BigInt.from_int(initial_quantity) if fungible else BigInt.one()
	
## The flag only applies for serializing the [member MintCip68Pair.extra_plutus_data].
## The CIP25 metadata follows its own rules.
func to_data() -> Variant:
	# We add the standard fields on top of the non-standard ones, overwriting.
	var cip25_metadata := non_standard_metadata
	cip25_metadata["name"] = name
	cip25_metadata["image"] = image
	cip25_metadata["mediaType"] = media_type
	if description != "":
		cip25_metadata["description"] = description
	if (not file_details.is_empty()):
		var file_details_converted : Array = []
		for fd: FileDetails in file_details:
			file_details_converted.push_back(fd.as_dict())
		cip25_metadata["files"] = file_details_converted
	var cip25_metadata_homogenized = _homogenize_or_fail(cip25_metadata)
	var cip68_datum := \
		Constr.new(BigInt.zero(), [
			cip25_metadata_homogenized,
			BigInt.one(),
			extra_plutus_data,
		])
	return cip68_datum

var big_int_script : Script = preload("res://addons/@mlabs-haskell/godot-cardano/src/big_int.gd")
var file_details_script : Script = preload("res://addons/@mlabs-haskell/godot-cardano/src/file_details.gd")

# Convert any non-strict keys and values to their strict PlutusData counterpart
# (if possible). Fail if invalid types are found by returning null.
func _homogenize_or_fail(v: Variant) -> PlutusData:
	match typeof(v):
		TYPE_STRING:
			return PlutusBytes.new((v as String).to_utf8_buffer())
		TYPE_INT:
			return BigInt.from_int(v)
		TYPE_PACKED_BYTE_ARRAY:
			return v
		TYPE_ARRAY:
			var homogenized_v = []
			for val in v:
				var homogenized_val = _homogenize_or_fail(val)
				if homogenized_val == null:
					return null
				else:
					homogenized_v.push_back(homogenized_val)
			return homogenized_v
		TYPE_DICTIONARY:
			var homogenized_v: Dictionary = {}
			for key in v:
				var homogenized_key
				if typeof(key) == TYPE_STRING:
					homogenized_key = PlutusBytes.new((key as String).to_utf8_buffer())
				elif typeof(key) == TYPE_PACKED_BYTE_ARRAY:
					homogenized_key = key
				else:
					assert(false
					, "Found key of neither type String nor PackedByteArray: "
					+ type_string(typeof(key)))
					return null
				var homogenized_val = _homogenize_or_fail(v[key])
				if homogenized_val == null:
					return null
				homogenized_v[homogenized_key] = homogenized_val
			return PlutusMap.new(homogenized_v)
		TYPE_OBJECT:
			var script = v.get_script()
			if script != big_int_script and script != file_details_script:
				assert(false, "Object script is not BigInt or FileDetails. Object script " + script)
				return null
			else:
				return v
		_:
			assert(false, "Found value of unexpected type " + type_string(typeof(v)))
			return null

func make_user_asset_class(script: PlutusScript) -> AssetClass:
	return AssetClass.new(
		PolicyId.from_script(script),
		get_user_token_name()
	)

func make_ref_asset_class(script: PlutusScript) -> AssetClass:
	return AssetClass.new(
		PolicyId.from_script(script),
		get_ref_token_name()
	)

func _validate_property(property):
	var hide_conditions: Array[bool] = [
		property.name == 'initial_quantity' and not self.fungible,
		property.name == 'extra_plutus_data_int' and extra_plutus_data_type != ExtraPlutusDataType.INT,
		property.name == 'extra_plutus_data_bytes' and extra_plutus_data_type != ExtraPlutusDataType.BYTES,
		property.name == 'extra_plutus_data_as_hex' and extra_plutus_data_type != ExtraPlutusDataType.BYTES,
		property.name == 'extra_plutus_data_as_utf8' and extra_plutus_data_type != ExtraPlutusDataType.BYTES,
		property.name == 'extra_plutus_data_json_path' and extra_plutus_data_type != ExtraPlutusDataType.JSON_FILE,
		property.name == 'extra_plutus_data_json' and extra_plutus_data_type != ExtraPlutusDataType.JSON_INLINE,
		property.name == 'extra_plutus_data_cbor_hex' and extra_plutus_data_type != ExtraPlutusDataType.CBOR_HEX,
	]
	var readonly_conditions: Array[bool] = [
		property.name == 'extra_plutus_data_json' and FileAccess.file_exists(extra_plutus_data_json_path)
	]
	if hide_conditions.any(func (x): return x):
		property.usage &= ~PROPERTY_USAGE_EDITOR
	if readonly_conditions.any(func (x): return x):
		property.usage |= PROPERTY_USAGE_READ_ONLY
