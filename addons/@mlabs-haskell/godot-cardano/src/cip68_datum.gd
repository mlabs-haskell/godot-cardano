class_name Cip68Datum
extends Constr

var _unwrapped: Dictionary

# TODO: validate structure
static func from_constr(data: Constr) -> Cip68Datum:
	var datum = new(data._constructor, data._fields)
	datum._unwrapped = datum._fields[0]._unwrap()
	return datum

func get_metadata(key: String, default: PlutusData = null) -> PlutusData:
	return PlutusData.wrap(_unwrapped.get(key.to_utf8_buffer(), default))

func name() -> String:
	return get_metadata("name")._unwrap().get_string_from_utf8()

func image_url() -> String:
	return get_metadata("image")._unwrap().get_string_from_utf8()

func media_type() -> String:
	return get_metadata("mediaType")._unwrap().get_string_from_utf8()

func description() -> String:
	return get_metadata("description")._unwrap().get_string_from_utf8()

# FIXME: not correct, shold return `Array[FileDetails]`
func files() -> PlutusData:
	return get_metadata("files")

func get_extra_plutus_data() -> PlutusData:
	return _fields[2]
