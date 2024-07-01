extends Resource
## CIP25 file details
##
## The CIP25 standard (and hence the CIP68 standard as well) defines an optional
## "file details" field that can be used to attach additional files to a token.
class_name FileDetails

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
