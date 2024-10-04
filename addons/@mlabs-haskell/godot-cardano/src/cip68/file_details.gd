extends Resource
class_name FileDetails

## CIP25 file details
##
## The CIP25 standard (and hence the CIP68 standard as well) defines an optional
## "file details" field that can be used to attach additional files to a token.

@export
var name: String = ""
@export
var media_type: String
@export
var src: String
@export
var additional_properties: Dictionary = {}

func as_dict():
	var dict := additional_properties
	dict["mediaType"] = media_type
	dict["src"] = src
	if name != "":
		dict["name"] = ""
	return dict

static func from_dict(dict: Dictionary) -> FileDetails:
	var file_details = new()
	file_details.additional_properties = dict.duplicate(true)
	file_details.media_type = file_details.additional_properties.media_type
	file_details.src = file_details.additional_properties.src
	file_details.name = ""
	if file_details.additional_properties.has("name"):
		file_details.name = file_details.additional_properties.name
	file_details.additional_properties.erase("mediaType")
	file_details.additional_properties.erase("src")
	file_details.additional_properties.erase("name")
	return file_details
