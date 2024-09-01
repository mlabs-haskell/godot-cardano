@tool
extends Resource
class_name Cip68Config

## Helper for minting valid CIP68 tokens
## 
## This resource is used for creating valid pairs of CIP68 _reference_
## and _user_ tokens, as described in the specification:
##
## https://cips.cardano.org/cip/CIP-0068
##
## This class runs assertions in the editor to validate that the provided
## metadata is valid for a CIP68 token. Whenever possible, it is recommended
## to create a resource in the inspector and edit the fields manually instead
## of programmatically to take advantage of this.

@export
## The minting policy associated with this CIP68 config. This minting policy
## must be used by both the ref and user tokens to satisfy the CIP68 specifications.
var minting_policy: ScriptResource
var minting_policy_source: PlutusScriptSource

@export_category("Token Name")
## The token name [b]body[/b] (i.e: the part of the token name
## that is not the CIP67 header).
@export
var token_name: PackedByteArray:
	set(v):
		token_name = v.slice(0,32)

# FIXME: Currently this doesn't work if you put one character at a time.
## The token name, hex-encoded.
@export
var token_name_as_hex: String:
	get:
		return token_name.hex_encode()
	set(v):
		if (v.length() % 2 == 0):
			token_name = v.hex_decode()

## The token name, UTF-8 encoded.
@export
var token_name_as_utf8: String:
	get:
		return token_name.get_string_from_utf8()
	set(v):
		token_name = v.to_utf8_buffer()

@export_category("CIP25 Metadata")
## The standard "name" field.
@export
var name: String
## The standard "image" field. This should be a valid URI.
@export
var image: String
@export_enum("image/webp", "image/jpeg", "image/gif", "image/png")
## The standard "mediaType" field.
var media_type: String = "image/webp"
## The standard "description" field.
@export
var description: String = ""
## An array of [FileDetails].
@export
var file_details : Array[FileDetails] = []
@export_category("Additional Metadata")
## This is [i]non-standard[/i], [i]optional[/i] CIP-25 metadata.[br][br]
##
## Use this for any additional fields you want to provide that are not
## required by the CIP25 standard. Any field names overlapping with standard field
## names (like "name" and "image") will be ignored.
##
## Keys of the dictionary should be [String]s, while values may be:[br][br]
## 1. [String] (which will be converted [PackedByteArray])[br]
## 2. [PackedByteArray][br]
## 3. [int] (which will be converted to [BigInt])[br]
## 4. [BigInt][br]
## 5. [Array], [b]but only if its elements are valid values[/b].[br]
## 6. [Dictionary], [b]but only if its keys and values are valid[/b].[br][br]
##
## Notably, you may not use neither [bool] nor [Constr]. If these conditions are
## too restrictive, take a look at [member Cip68ConfigPair.extra_plutus_data].
@export
var non_standard_metadata: Dictionary = {}:
	set(v):
		non_standard_metadata = v
		_homogenize_or_fail(non_standard_metadata)

@export_category("Extra Plutus Data")
@export
## This corresponds to the third field of the CIP-68 datum. Use this if you need
## to store data in any form that is not compliant with CIP-25. No restrictions
## apply other than the usual ones for encoding a datum.
var extra_plutus_data: PlutusDataResource = PlutusDataResource.new()

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
		
## Get the CIP68 user token name
func get_user_token_name() -> AssetName:
	var user_token_name := "000de140".hex_decode() if not fungible else "0014df10".hex_decode()
	user_token_name.append_array(token_name)
	return AssetName.from_bytes(user_token_name).value
	
## Get the CIP68 reference token name	
func get_ref_token_name() -> AssetName:
	var ref_token_name := "000643b0".hex_decode()
	ref_token_name.append_array(token_name)
	return AssetName.from_bytes(ref_token_name).value

func get_quantity() -> BigInt:
	return BigInt.from_int(initial_quantity) if fungible else BigInt.one()
	
## The flag only applies for serializing the [member Cip68ConfigPair.extra_plutus_data].
## The CIP25 metadata follows its own rules for serialization.
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
			extra_plutus_data.data,
		])
	return Cip68Datum.unsafe_from_constr(cip68_datum)

var big_int_script : Script = preload("res://addons/@mlabs-haskell/godot-cardano/src/plutus_data/big_int.gd")
var file_details_script : Script = preload("res://addons/@mlabs-haskell/godot-cardano/src/cip68/file_details.gd")

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
			var homogenized_v: Array[PlutusData] = []
			for val in v:
				var homogenized_val = _homogenize_or_fail(val)
				if homogenized_val == null:
					return null
				else:
					homogenized_v.push_back(homogenized_val)
			return PlutusList.new(homogenized_v)
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

func _make_asset_class(script_source: PlutusScriptSource, token_name: AssetName) -> AssetClass:
	if script_source == null:
		push_error("Could not make CIP68 asset class: set minting_policy_source or provide a script source")
		return null
	return AssetClass.new(
		PolicyId.from_script_source(script_source),
		token_name
	)
	
func make_user_asset_class(script_source := minting_policy_source) -> AssetClass:
	return _make_asset_class(script_source, get_user_token_name())

func make_ref_asset_class(script_source := minting_policy_source) -> AssetClass:
	return _make_asset_class(script_source, get_ref_token_name())

func _validate_property(property):
	var hide_conditions: Array[bool] = [
		property.name == 'initial_quantity' and not self.fungible,
	]
	if hide_conditions.any(func (x): return x):
		property.usage &= ~PROPERTY_USAGE_EDITOR

## Load the minting policy from file or by querying the Provider. This must be
## performed in before most actions with this config will be possible.
func init_script(provider: Provider) -> void:
	minting_policy_source = await provider.load_script(minting_policy)
