@tool
extends Resource
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

class_name MintCip68Pair

@export_category("Token Name")
## The token name [b]body[/b] (i.e: the part of the token name
## that is not the CIP67 header).
@export
var token_name: PackedByteArray:
	set(v):
		token_name = v

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
## The standard "mediaType" field.
@export
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
## too restrictive, take a look at [member MintCip68Pair.extra_plutus_data].
@export
var non_standard_metadata: Dictionary = {}:
	set(v):
		non_standard_metadata = v
		_homogenize_or_fail(non_standard_metadata)
@export
## This corresponds to the third field of the CIP-68 datum. Use this if you need
## to store data in any form that is not compliant with CIP-25. No restrictions
## apply other than the usual ones for encoding a datum.
var extra_plutus_data: Dictionary = {}:
	set(v):
		assert(PlutusData.serialize(v, true).is_ok()
		, "Failed to do strict serialization of extra_plutus_data")
	
## Get the CIP68 user token name
func get_user_token_name() -> PackedByteArray:
	var user_token_name := "000de140".hex_decode()
	user_token_name.append_array(token_name)
	return user_token_name

## Get the CIP68 reference token name	
func get_ref_token_name() -> PackedByteArray:
	var ref_token_name := "000643b0".hex_decode()
	ref_token_name.append_array(token_name)
	return ref_token_name
	
## The flag only applies for serializing the [member MintCip68Pair.extra_plutus_data].
## The CIP25 metadata follows its own rules for serialization.
func to_data(_strict: bool) -> Variant:
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
func _homogenize_or_fail(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING:
			return (v as String).to_utf8_buffer()
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
					homogenized_key = (key as String).to_utf8_buffer()
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
			return homogenized_v
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
