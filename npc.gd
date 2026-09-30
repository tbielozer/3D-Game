extends CharacterBody3D

const SPEED = 3.0
const TARGET_SPEED = 20.0
const ACCEL = 20.0                # how quickly it speeds up / slows down
const TURN_SPEED = 4.0
const WANDER_RADIUS = 20.0
const WALK_TIME_RANGE = Vector2(3.0, 8.0)   # seconds spent walking per wander
const IDLE_TIME_RANGE = Vector2(2.0, 6.0)   # seconds spent standing still
const IDLE_CHANCE = 0.4           # chance to stand still after each walk
const HIT_COOLDOWN_DURATION = 1.0

enum State { IDLE, WANDER }

@onready var detection_area: Area3D = $Area3D

@export var npc_power = 100

var state: State = State.IDLE
var state_timer: float = 0.0
var target_player: Node3D = null
var spawn_position: Vector3
var wander_target: Vector3
var hit_cooldown: float = 0.0
var target: bool = false
var knockback = Vector3.ZERO
var stagger_time := 0.0

@onready var terrain: Terrain = get_tree().current_scene.get_node("StaticBody3D2")

@onready var x_lim: float = terrain.size.x / 2.0 - 1.0
@onready var z_lim: float = terrain.size.y / 2.0 - 1.0

func _ready() -> void:
	spawn_position = global_position
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	_next_wander_state()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		target_player = body

func _on_body_exited(body: Node) -> void:
	if body == target_player:
		target_player = null

func _next_wander_state() -> void:
	if randf() < IDLE_CHANCE:
		state = State.IDLE
		state_timer = randf_range(IDLE_TIME_RANGE.x, IDLE_TIME_RANGE.y)
	else:
		state = State.WANDER
		state_timer = randf_range(WALK_TIME_RANGE.x, WALK_TIME_RANGE.y)
		wander_target = spawn_position + Vector3(
			randf_range(-WANDER_RADIUS, WANDER_RADIUS), 0,
			randf_range(-WANDER_RADIUS, WANDER_RADIUS))

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
		
	if position.y < -10:
		position.y = 5
		position.x = 0
	if abs(position.x) > x_lim:
		velocity.x = -velocity.x
	if abs(position.z) > z_lim:
		velocity.z = -velocity.z

	if hit_cooldown > 0.0:
		hit_cooldown -= delta

	if not is_on_floor():
		velocity += get_gravity() * delta

	var move_direction := Vector3.ZERO

	if is_instance_valid(target_player):
		move_direction = target_player.global_position - global_position
		target = true
	else:
		target = false
		state_timer -= delta
		var to_target := wander_target - global_position
		to_target.y = 0
		if state_timer <= 0.0 or (state == State.WANDER and to_target.length() < 1.0):
			state = State.WANDER if state == State.IDLE else State.IDLE
			_next_wander_state()
		if state == State.WANDER:
			move_direction = to_target

	move_direction.y = 0
	move_direction = move_direction.normalized() if move_direction.length() > 0.01 else Vector3.ZERO

	# Turn toward the direction of travel.
	if move_direction != Vector3.ZERO:
		var target_yaw := atan2(-move_direction.x, -move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)

	# Accelerate smoothly instead of snapping to full speed / zero.
	if (stagger_time > 0):
		stagger_time -= delta
	elif is_on_floor():
		var speed := TARGET_SPEED if target else SPEED
		var target_vel := Vector2(move_direction.x, move_direction.z) * speed
		var horizontal := Vector2(velocity.x, velocity.z).move_toward(target_vel, ACCEL * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.y
	velocity += knockback
	knockback = Vector3.ZERO

	move_and_slide()

	if hit_cooldown <= 0.0:
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider()
			if collider and collider.is_in_group("players"):
				_on_hit_player(collider)
				hit_cooldown = HIT_COOLDOWN_DURATION
				break

func _on_hit_player(player: Node) -> void:
	var push_dir = player.global_position - global_position
	push_dir.y = 0
	push_dir = push_dir.normalized() if push_dir.length() > 0.01 else Vector3.FORWARD
	player.bouncy_bullet.rpc_id(player.name.to_int(), push_dir, npc_power)
	
func hit_by_car(dir: Vector3, power: float) -> void:
	knockback = Vector3(dir.x, 0, dir.z) * power + Vector3.UP * (power * 0.5)
	stagger_time = 0.5
