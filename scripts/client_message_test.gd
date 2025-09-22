extends Control

@onready var rich_text_label: RichTextLabel = $VBoxContainer/HBoxContainer/RichTextLabel
@onready var line_edit: LineEdit = $VBoxContainer/HBoxContainer/LineEdit

func _ready() -> void:
	GameServer.connect("new_message_posted", update_last_msg)

func _on_line_edit_text_submitted(new_text: String) -> void:
	line_edit.clear()
	GameServer.post_message(new_text)

func update_last_msg(msg: String) -> void:
	rich_text_label.append_text("\n"+msg)
