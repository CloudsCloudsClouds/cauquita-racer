class_name CameraFollowCar
extends Camera3D

@export var objective: RigidBody3D

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	
	look_at(objective.position, Vector3.UP)
	
