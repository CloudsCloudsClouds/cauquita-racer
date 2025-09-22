class_name LobbyManager
extends Resource


# The input format of players are dictionaries. In the form of
# {"device": int, "color": Color, "vehicle": int}
# or something.
var players: Array

# HACK: This only accepts colors!
func add_player(device: int, color: Color) -> void:
	players.append({"device": device, "color": color})

# First time using lambda functions. Love it so far
func remove_player(device: int) -> void:
	players = players.filter(func(p): return p.device != device)

func add_player_simple(device: int) -> void:
	players.append({"device": device, "color": Color.WHITE, "ready": false})


func set_player_ready(device: int, ready: bool) -> void:
	for p in players:
		if p.device == device:
			p.ready = ready

func all_players_ready() -> bool:
	return players.all(func(p): return p.ready) and players.size() > 0
