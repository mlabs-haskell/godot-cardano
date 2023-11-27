extends _Cardano

class_name Cardano

func _init(provider: Provider):
	self.provider = provider
	provider.got_parameters.connect(_on_got_parameters)
	provider.get_parameters()

func _on_got_parameters(params: ProtocolParameters):
	set_protocol_parameters(params)
