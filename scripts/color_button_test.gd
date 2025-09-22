extends Button

@onready var lobby: Node = $"../../../../../../.."
@onready var color_rect: ColorRect = $"../../ColorRect"

@export var color: Color

func _ready() -> void:
	connect("pressed", _on_pressed)

func _on_pressed() -> void:
	lobby.on_color_selected(-1, color)
	color_rect.color = color
