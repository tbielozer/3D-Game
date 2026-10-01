extends VehicleBody3D

@onready var camera: Camera3D = $Camera3D

const MAX_ENGINE_FORCE = 300.0
const MAX_STEER = 0.4
const MAX_BRAKE = 3.0

@export var driver_id: int = -1  # synced via MultiplayerSynchronizer; car's node authority stays on the server always

var _throttle: float = 0.0
var _steer_input: float = 0.0
var _braking: bool = false

func _ready() -> void:
	add_to_group("cars")
	camera.current = false
	body_entered.connect(_on_body_entered)
	
@onready var terrain: Terrain = get_tree().current_scene.get_node("StaticBody3D2")

@onready var x_lim: float = terrain.size.x / 2.0 - 1.0
@onready var z_lim: float = terrain.size.y / 2.0 - 1.0

func _physics_process(delta: float) -> void:
	# Anyone who IS the current driver samples their own local input and sends it up.
	# (call_local on the RPC means the host, if driving, also updates itself immediately.)
	if driver_id == multiplayer.get_unique_id():
		var throttle := Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
		var steer_input := Input.get_action_strength("ui_left") - Input.get_action_strength("ui_right")
		submit_input.rpc_id(1, throttle, steer_input, Input.is_action_pressed("ui_accept"))

	# Only the server actually drives the physics simulation.
	if multiplayer.is_server():
		if driver_id == -1:
			engine_force = 0.0
			steering = move_toward(steering, 0.0, delta * 2.0)
			brake = 0.0
			return
		engine_force = _throttle * MAX_ENGINE_FORCE
		steering = move_toward(steering, _steer_input * MAX_STEER, delta * 3.0)
		brake = MAX_BRAKE if _braking else 0.0
		if position.y < -10:
			position.y = 5
			position.x = 0
		if abs(position.x) > x_lim:
			if position.x < 0:
				position.x = -x_lim
			else:
				position.x = x_lim
		if abs(position.z) > z_lim:
			if position.z < 0:
				position.z = -z_lim
			else:
				position.z = z_lim

# Sent by the current driver's client every physics frame; ignored from anyone else.
@rpc("any_peer", "call_local", "unreliable")
func submit_input(throttle: float, steer_input: float, braking: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != driver_id and multiplayer.get_remote_sender_id() != 0:
		return  # get_remote_sender_id() is 0 for a local call_local invocation (host driving their own car)
	_throttle = throttle
	_steer_input = steer_input
	_braking = braking


@rpc("any_peer", "call_local", "reliable")
func request_enter(id: int) -> void:
	if not multiplayer.is_server():
		return
	if driver_id != -1:
		return
	driver_id = id
	enter_confirmed.rpc_id(id)

@rpc("any_peer", "call_local", "reliable")
func request_exit() -> void:
	if not multiplayer.is_server():
		return
	if driver_id == -1:
		return
	var leaving_id = driver_id
	driver_id = -1
	exit_confirmed.rpc_id(leaving_id, global_position + global_transform.basis.x * 2.0)

@rpc("authority", "call_local", "reliable")
func enter_confirmed() -> void:
	camera.current = true
	var my_player = get_tree().current_scene.get_node(str(multiplayer.get_unique_id()))
	my_player._on_enter_car(self)

@rpc("authority", "call_local", "reliable")
func exit_confirmed(exit_pos: Vector3) -> void:
	camera.current = false
	var my_player = get_tree().current_scene.get_node(str(multiplayer.get_unique_id()))
	my_player._on_exit_car(exit_pos)
	
	
func _on_body_entered(body: Node3D) -> void:
	print("car touched: ", body.name)
	if not multiplayer.is_server():
		return
	if body.has_method("hit_by_car"):
		print("hit pedestrian")
		var speed := linear_velocity.length()
		if speed < 3.0:
			return
		var push_dir := linear_velocity
		push_dir.y = 0
		push_dir = push_dir.normalized() if push_dir.length() > 0.01 else Vector3.FORWARD
		body.hit_by_car(push_dir, speed * 1.5)
	if body.is_in_group("players"):
		if body.has_method("bouncy_bullet"):
			print("Player hit")
			var push_dir = (body.global_position - global_position)
			push_dir.y = 0
			#var current_dir = linear_velocity.normalized() if linear_velocity.length() > 0.01 else Vector3.FORWARD
			push_dir = push_dir.normalized() if push_dir.length() > 0.01 else Vector3.FORWARD
			body.rpc_id(body.name.to_int(), "bouncy_bullet", push_dir, 50)
