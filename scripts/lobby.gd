extends Node

@export var lobby_manager: LobbyManager
@export_file_path("*.tscn") var go_to_scene: String

func _ready() -> void:
	lobby_manager.players.clear()

func _process(_delta: float) -> void:
	handle_join_leave_input()

func handle_join_leave_input() -> void:
	var all_devices = Input.get_connected_joypads() + [-1]

	for device in all_devices:
		if MultiplayerInput.is_action_just_pressed(device, "join"):
			if not is_device_joined(device):
				lobby_manager.add_player_simple(device)
				print_debug("Player joined with device: ", device)
				
		if MultiplayerInput.is_action_just_pressed(device, "leave"):
			if is_device_joined(device):
				lobby_manager.remove_player(device)
				print("Player left with device: ", device)
				
		if MultiplayerInput.is_action_just_pressed(device, "ready"):
			if is_device_joined(device):
				var player = get_player_by_device(device)
				lobby_manager.set_player_ready(device, not player.ready)
				print("Player ready status: ", player.ready)


func is_device_joined(device: int) -> bool:
	return lobby_manager.players.any(func(p): return p.device == device)

func get_player_by_device(device: int):
	return lobby_manager.players.filter(func(p): return p.device == device)[0]
