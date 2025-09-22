extends Node

var message_data: PackedStringArray = []
var player_info: Array = []

signal new_message_posted(msg: String)

func get_message(id: int) -> String:
	if message_data.size() < id:
		return message_data[id]
	else:
		return error_string(5)

func post_message(msg: String) -> void:
	message_data.append(msg)
	emit_signal("new_message_posted", msg)

func get_last_message() -> String:
	return message_data[-1]
