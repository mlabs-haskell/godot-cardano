class_name Cip68Datum
extends Constr

var _unwrapped: Dictionary

# TODO: validate structure
static func unsafe_from_constr(data: Constr) -> Cip68Datum:
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
	var description = get_metadata("description")
	return "" if description == null else description._unwrap().get_string_from_utf8()

func files() -> Array[FileDetails]:
	var files: PlutusList = get_metadata("files")
	var result: Array[FileDetails] = []
	if files != null:
		for file: PlutusMap in files.get_data():
			result.push_back(FileDetails.from_dict(file.get_data()))
			pass
	return result

func extra_plutus_data() -> PlutusData:
	return _fields[2]

func copy_to_conf(conf: Cip68Config) -> void:
	conf.name = name()
	conf.image = image_url()
	conf.media_type = media_type()
	conf.description = description()
	conf.extra_plutus_data.data = extra_plutus_data()
