extends RigidBody3D

# --- Ruedas (RaycastWheel) ---
@export var wheels: Array[RaycastWheel]              # Orden según tu escena: [WheelFL, WheelRL, WheelFR, WheelRR]
@onready var wFL: RaycastWheel = $WheelFL
@onready var wFR: RaycastWheel = $WheelFR
@onready var wRL: RaycastWheel = $WheelRL
@onready var wRR: RaycastWheel = $WheelRR

# Marcas de derrape (opcional)
@export var skid_marks: Array[GPUParticles3D]        # 4 partículas (SkidMaks/*)

# Curva de aceleración (0..1)
@export var accel_curve: Curve

# Movimiento y dirección
@export var acceleration: float = 600.0
@export var max_speed: float = 20.0
@export var tire_turn_speed: float = 2.0
@export var tire_max_turn_degress: float = 25.0

# Estabilidad / rozamiento longitudinal
@export var z_traction: float = 0.12
@export var anti_roll_strength: float = 0.0  # 0 = apagado; prueba 300–600 si hay mucho balanceo

# Freno / derrape
var hand_break: bool = false
var is_slipping: bool = false

# Entrada motor: -1, 0, 1
var motor_input: int = 0

# --- TURBO (E) ---
@export var turbo_multiplier: float = 1.9         # fuerza extra del motor
@export var turbo_duration: float = 1.6           # segundos activos
@export var turbo_cooldown: float = 3.0           # recarga total
@export var turbo_speed_boost: float = 1.4        # sube la Vmax mientras dure
@export var turbo_min_ac: float = 0.35            # empuje mínimo del turbo (si tu accel_curve cae mucho)
var turbo_active: bool = false
var turbo_time_left: float = 0.0
var turbo_cd_left: float = 0.0

# FX de Turbo (partículas opcionales)
@export var turbo_fx: Array[GPUParticles3D]       # arrastra 1 o 2 GPUParticles3D (escape izq/der)

# Cámara / FOV
@onready var cam: Camera3D = $Camera3D
@export var camera_fov_normal: float = 70.0
@export var camera_fov_turbo: float = 82.0
@export var camera_fov_lerp: float = 6.0          # rapidez con que interpola el FOV

func _ready() -> void:
	# Centro de masa bajo y dampings para quitar rebote
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	linear_damp = 0.1
	angular_damp = 4.0

	# Autollenar skid_marks si existe el nodo "SkidMaks"
	if skid_marks.is_empty() and has_node("SkidMaks"):
		for n in $"SkidMaks".get_children():
			if n is GPUParticles3D:
				skid_marks.append(n)

	# Dejar FOV normal al inicio
	if cam:
		cam.fov = camera_fov_normal


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("handbreak"):
		hand_break = true
		is_slipping = true
	elif event.is_action_released("handbreak"):
		hand_break = false

	if event.is_action_pressed("accelerate"):
		motor_input = 1
	elif event.is_action_released("accelerate"):
		motor_input = 0

	if event.is_action_pressed("decelerate"):
		motor_input = -1
	elif event.is_action_released("decelerate"):
		motor_input = 0

	if event.is_action_pressed("turbo"):   # tecla E
		_try_activate_turbo()


func _basic_steering_rotation(delta: float) -> void:
	# Giramos las ruedas delanteras (RayCast) en Y como pivotes
	var turn_input: float = Input.get_axis("turn_right", "turn_left") * tire_turn_speed

	# Reducir giro a alta velocidad (más estabilidad)
	var speed: float = linear_velocity.length()
	var speed_factor: float = clampf(1.0 - (speed / (max_speed * 1.5)), 0.25, 1.0)
	var max_turn: float = deg_to_rad(tire_max_turn_degress) * speed_factor

	if turn_input != 0.0:
		wFL.rotation.y = clampf(wFL.rotation.y + turn_input * delta, -max_turn, max_turn)
		wFR.rotation.y = clampf(wFR.rotation.y + turn_input * delta, -max_turn, max_turn)
	else:
		wFL.rotation.y = move_toward(wFL.rotation.y, 0.0, tire_turn_speed * delta)
		wFR.rotation.y = move_toward(wFR.rotation.y, 0.0, tire_turn_speed * delta)


func _physics_process(delta: float) -> void:
	_basic_steering_rotation(delta)

	# Timers del turbo
	if turbo_active:
		turbo_time_left -= delta
		if turbo_time_left <= 0.0:
			_set_turbo_visuals(false)
			turbo_active = false

	if turbo_cd_left > 0.0:
		turbo_cd_left = max(turbo_cd_left - delta, 0.0)

	# Interpolar FOV según estado de turbo
	if cam:
		var target_fov: float = camera_fov_turbo if turbo_active else camera_fov_normal
		cam.fov = lerpf(cam.fov, target_fov, delta * camera_fov_lerp)

	# Ruedas
	var grounded: bool = false
	var id: int = 0

	var fl_comp: float = 0.0
	var fr_comp: float = 0.0
	var rl_comp: float = 0.0
	var rr_comp: float = 0.0

	for ray in wheels:
		ray.force_raycast_update()
		if ray.is_colliding():
			grounded = true

		_do_single_wheel_suspension(ray)
		_do_single_wheel_acceleration(ray)
		_do_single_wheel_traccion(ray, id)

		if anti_roll_strength > 0.0 and ray.is_colliding():
			var spring_len: float = ray.global_position.distance_to(ray.get_collision_point()) - ray.wheel_radius
			var comp: float = ray.rest_dist - spring_len
			match id:
				0: fl_comp = comp   # 0 FL
				1: rl_comp = comp   # 1 RL
				2: fr_comp = comp   # 2 FR
				3: rr_comp = comp   # 3 RR

		id += 1

	if anti_roll_strength > 0.0 and grounded and wheels.size() >= 4:
		_apply_anti_roll(fl_comp, fr_comp, wFL, wFR)
		_apply_anti_roll(rl_comp, rr_comp, wRL, wRR)


func _apply_anti_roll(left_comp: float, right_comp: float, left_w: RaycastWheel, right_w: RaycastWheel) -> void:
	var diff: float = (left_comp - right_comp) * anti_roll_strength
	var n_left: Vector3 = left_w.get_collision_normal()
	var n_right: Vector3 = right_w.get_collision_normal()
	if left_w.is_colliding():
		apply_force(-n_left * diff, left_w.wheel.global_position - global_position)
	if right_w.is_colliding():
		apply_force(n_right * diff, right_w.wheel.global_position - global_position)


func _get_point_velocity(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - global_position)


func _do_single_wheel_traccion(ray: RaycastWheel, idx: int) -> void:
	if not ray.is_colliding():
		return

	var steer_side_dir: Vector3 = ray.global_basis.x
	var tire_vel: Vector3 = _get_point_velocity(ray.wheel.global_position)

	var vel_len: float = max(tire_vel.length(), 0.001)
	var steering_x_vel: float = steer_side_dir.dot(tire_vel)
	var grip_factor: float = clampf(absf(steering_x_vel / vel_len), 0.0, 1.0)
	var x_traction: float = ray.grip_curve.sample_baked(grip_factor)

	# Skid marks
	if skid_marks.size() > idx:
		skid_marks[idx].global_position = ray.get_collision_point() + Vector3.UP * 0.01
		skid_marks[idx].look_at(skid_marks[idx].global_position + global_basis.z)

	if not hand_break and grip_factor < 0.2:
		is_slipping = false
		if skid_marks.size() > idx: skid_marks[idx].emitting = false

	if hand_break:
		x_traction = 0.01
		if skid_marks.size() > idx and not skid_marks[idx].emitting:
			skid_marks[idx].emitting = true
	elif is_slipping:
		x_traction = 0.1

	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var x_force: Vector3 = -steer_side_dir * steering_x_vel * x_traction * ((mass * gravity) / 4.0)

	# Rozamiento longitudinal alineado a la rueda (mejora recta)
	var f_vel: float = -ray.global_basis.z.dot(tire_vel)
	var z_force: Vector3 = ray.global_basis.z * f_vel * z_traction * ((mass * gravity) / 4.0)

	var force_pos: Vector3 = ray.wheel.global_position - global_position
	apply_force(x_force, force_pos)
	apply_force(z_force, force_pos)


func _do_single_wheel_acceleration(ray: RaycastWheel) -> void:
	var forward_dir: Vector3 = -ray.global_basis.z
	var vel: float = forward_dir.dot(linear_velocity)

	# Giro visual rueda
	ray.wheel.rotate_x((-vel * get_process_delta_time()) / ray.wheel_radius)

	if not ray.is_colliding():
		return

	var force_pos: Vector3 = ray.wheel.global_position - global_position

	if ray.is_motor and motor_input != 0:
		var eff_max_speed: float = max_speed * (turbo_speed_boost if turbo_active else 1.0)
		var speed_ratio: float = clampf(absf(vel) / eff_max_speed, 0.0, 1.0)
		var ac: float = accel_curve.sample_baked(speed_ratio)

		# Empuje mínimo cuando hay turbo (por si la curva cae mucho)
		if turbo_active:
			ac = max(ac, turbo_min_ac)

		var eff_accel: float = acceleration * (turbo_multiplier if turbo_active else 1.0)

		# Evitar empujar muy por encima del tope
		if absf(vel) > eff_max_speed * 1.05:
			return

		var force_vector: Vector3 = forward_dir * eff_accel * motor_input * ac
		apply_force(force_vector, force_pos)


func _do_single_wheel_suspension(ray: RaycastWheel) -> void:
	if not ray.is_colliding():
		return

	ray.target_position.y = -(ray.rest_dist + ray.wheel_radius + ray.over_extend)

	var contact: Vector3 = ray.get_collision_point()
	var spring_up_dir: Vector3 = ray.global_transform.basis.y
	var spring_len: float = ray.global_position.distance_to(contact) - ray.wheel_radius
	var offset: float = ray.rest_dist - spring_len

	# Visual
	ray.wheel.position.y = -spring_len

	# Resorte + amortiguación
	var spring_force: float = ray.spring_strength * offset
	var world_vel: Vector3 = _get_point_velocity(contact)
	var relative_velocity: float = spring_up_dir.dot(world_vel)
	var spring_damp_force: float = ray.spring_damping * relative_velocity

	var force_vector: Vector3 = (spring_force - spring_damp_force) * ray.get_collision_normal()
	var force_pos_offset: Vector3 = ray.wheel.global_position - global_position
	apply_force(force_vector, force_pos_offset)


# -------- TURBO --------
func _try_activate_turbo() -> void:
	if turbo_cd_left > 0.0:
		return

	# Al menos una rueda toca suelo
	var any_grounded: bool = false
	for ray in wheels:
		ray.force_raycast_update()
		if ray.is_colliding():
			any_grounded = true
			break
	if not any_grounded:
		return

	# (Opcional) solo si está acelerando hacia adelante:
	# if motor_input != 1: return

	turbo_active = true
	turbo_time_left = turbo_duration
	turbo_cd_left = turbo_cooldown + turbo_duration
	_set_turbo_visuals(true)
	# Debug opcional:
	# print("TURBO ON | vel=", linear_velocity.length())


func _set_turbo_visuals(active: bool) -> void:
	# Partículas
	for p in turbo_fx:
		if p:
			p.emitting = active
	# Cámara (FOV se interpola en _physics_process)
