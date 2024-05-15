extends Resource

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
