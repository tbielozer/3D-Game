extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const dash = 1.5
const max_shots = 2

var bullet_scene = preload("res://Bullet.tscn")
# NOTE: update this path to match wherever your Bullet scene actually lives.

@onready var camera: Camera3D = $Camera3D
@onready var muzzle: Marker3D = $Camera3D/Muzzle
# A Marker3D positioned slightly in front of the camera, so bullets spawn
# from "the barrel" rather than from inside the player's own body.
# Add a Marker3D as a child of Camera3D in the editor if you don't have one yet.

var highlight_target: Node = null
var highlight_material: StandardMaterial3D

var knockback: Vector3 = Vector3.ZERO
const KNOCKBACK_DECAY = 10.0  # tune to taste

var stagger_time: float = 0.0
const STAGGER_DURATION = 0.25  # tune this — how long input is locked out after a hit

@export var shot_count = 2

#wall stuff
var wall_scene = preload("res://wall.tscn")
var wall_mode: bool = false
var preview_wall: Wall = null
var wall_width: float = 4.0
var wall_height: float = 2.5
var wall_thickness: float = 0.2
var wall_tilt: float = 0
var wall_angle: float = 0
const WALL_RESIZE_STEP = 0.25
const WALL_ANGLE_STEP = 0.05
const WALL_PLACE_DISTANCE = 5.0  # fallback distance if raycast hits nothing
var wall_edit = 0

@onready var interact_area: Area3D = $InteractArea
var current_car: Node = null
var nearby_car: Node = null

@onready var terrain: Terrain = get_tree().current_scene.get_node("StaticBody3D2")

@onready var x_lim: float = terrain.size.x / 2.0 - 1.0
@onready var z_lim: float = terrain.size.y / 2.0 - 1.0

var car_scene = preload("res://car1.tscn")  # update to your actual car scene path
const CAR_SPAWN_HEIGHT = 2.0  # drop the car in from slightly above so it doesn't clip the terrain
const MAX_CARS = 5

var delete_mode: bool = false
const DELETE_RANGE = 50.0


var paint_mode: bool = false
const PAINT_COLORS = [Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.MAGENTA, Color.WHITE, Color.BLACK]
var paint_index: int = 0


@rpc("any_peer", "call_local", "reliable")
func set_spawn_position(pos: Vector3) -> void:
	# Called BY the server, targeted at the specific client who owns this
	# character (see NetworkManager._spawn_player). We can't just set
	# global_position directly from the server for this node, because the
	# owning client's MultiplayerSynchronizer won't accept incoming position
	# updates for a node it has authority over - it expects to be the one
	# driving its own position, not receiving it. An explicit RPC sidesteps
	# that by directly telling the owning client's own local copy to move.
	global_position = pos
	velocity = Vector3.ZERO
	# Zeroing velocity too, in case any residual gravity/fall speed had
	# already accumulated before this runs.


func _ready() -> void:
	# --- Multiplayer authority setup ---
	# The node's name was set to the owning peer's unique ID when it was spawned
	# (see NetworkManager._spawn_player). Every peer independently sets authority
	# here based on that name, rather than relying on the server's authority
	# assignment propagating over the network - this guarantees all peers agree
	# on who owns this player, even if replication timing is inconsistent.
	set_multiplayer_authority(str(name).to_int())

	if not is_multiplayer_authority():
		# This is true for player instances that belong to OTHER peers, not us.
		# We disable the camera so we don't have 4 cameras fighting for the view,
		# and skip input processing entirely below.
		camera.current = false
		set_process_unhandled_input(false)
		set_physics_process(false)
		return

	# Only runs for the player WE own:
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

var cursor_here = false
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event.is_action_pressed("ui_cancel") and not cursor_here:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cursor_here = true
	elif event.is_action_pressed("ui_cancel") and cursor_here:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		cursor_here = false
	
	if event.is_action_pressed("unstick"):
		position.y += 10
	
	if event.is_action_pressed("reload") and shot_count < max_shots:
		shot_count = shot_count + 1

	if event.is_action_pressed("action"):
		# Only the owning player should be able to trigger their own shots -
		# this function only runs at all for the authority (see _ready's
		# set_process_unhandled_input(false) for non-owned instances), so no
		# extra check is needed here.
		#request_fire.rpc_id(1, muzzle.global_position, -camera.global_transform.basis.z)
		# rpc_id(1, ...) sends this specifically to peer 1, which is ALWAYS
		# the server/host in Godot's high-level multiplayer - regardless of
		# who's currently running this code. -camera.basis.z is the direction
		# the camera is currently facing (forward in Godot is -Z).
		if delete_mode:
			_try_delete_target()
		elif paint_mode:
			_try_paint_target()
		elif wall_mode:
			_try_place_wall()
		elif shot_count > 0:
			request_fire.rpc_id(1, muzzle.global_position, -camera.global_transform.basis.z)
			shot_count = shot_count - 1
		
	if event.is_action_pressed("delete"):
		_toggle_delete_mode()
		
	if event.is_action_pressed("place_wall"):
			if wall_mode:
				_exit_wall_mode()
			else:
				_enter_wall_mode()

	#wall_edit
	#0 = width, 1 = height, 2 = thickness, 3 = tilt, 4- angle
	if wall_mode:
		if event.is_action_pressed("toggle"):
			if wall_edit < 4:
				wall_edit += 1
			else:
				wall_edit = 0
		if wall_edit == 0:
			if event.is_action_pressed("scroll_up"):
				wall_width += WALL_RESIZE_STEP
			if event.is_action_pressed("scroll_down"):
				wall_width = max(0.5, wall_width - WALL_RESIZE_STEP)
		elif wall_edit == 1:
			if event.is_action_pressed("scroll_up"):
				wall_height += WALL_RESIZE_STEP
			if event.is_action_pressed("scroll_down"):
				wall_height = max(0.5, wall_height - WALL_RESIZE_STEP)
		elif wall_edit == 2:
			if event.is_action_pressed("scroll_up"):
				wall_thickness += WALL_RESIZE_STEP
			if event.is_action_pressed("scroll_down"):
				wall_thickness = max(0.5, wall_thickness - WALL_RESIZE_STEP)
		elif wall_edit == 3:
			if event.is_action_pressed("scroll_up"):
				wall_tilt += WALL_ANGLE_STEP
			if event.is_action_pressed("scroll_down"):
				wall_tilt -= WALL_ANGLE_STEP
		elif wall_edit == 4:
			if event.is_action_pressed("scroll_up"):
				wall_angle += WALL_ANGLE_STEP
			if event.is_action_pressed("scroll_down"):
				wall_angle -= WALL_ANGLE_STEP
	
	if event.is_action_pressed("place_car"):
		_try_place_car()
			
	if event.is_action_pressed("interact"):
		if current_car:
			current_car.request_exit.rpc_id(1)
		elif nearby_car:
			nearby_car.request_enter.rpc_id(1, multiplayer.get_unique_id())
		
	if event.is_action_pressed("paint"):
		print("entered paint mode")
		paint_mode = not paint_mode
		if paint_mode:
			delete_mode = false
			if wall_mode:
				_exit_wall_mode()
	if paint_mode:
		if event.is_action_pressed("scroll_up"):
			paint_index = (paint_index + 1) % PAINT_COLORS.size()
		if event.is_action_pressed("scroll_down"):
			paint_index = (paint_index - 1 + PAINT_COLORS.size()) % PAINT_COLORS.size()


@rpc("any_peer", "call_local", "reliable")
func request_fire(spawn_pos: Vector3, direction: Vector3) -> void:
	# Runs on the SERVER only (any_peer lets any client call this and have it
	# execute here - see the "any_peer" note on set_spawn_position earlier).
	if not multiplayer.is_server():
		return

	var bullet = bullet_scene.instantiate()
	bullet.name = "Bullet_" + str(ResourceUID.create_id())
	bullet.global_position = spawn_pos
	bullet.direction = direction
	get_tree().current_scene.add_child(bullet)
	# Spawned under current_scene, so MultiplayerSpawner (configured to watch
	# that path, with Bullet added to its Auto Spawn List) replicates this
	# creation to every client automatically - same pattern as player spawning.
	


func _physics_process(delta: float) -> void:
	# This whole function only ever runs on the owning peer (see _ready above),
	# and the resulting position/rotation gets sent to everyone else
	# automatically via the MultiplayerSynchronizer node in this scene.
	
	if position.y < -10:
		position.y = 5
		position.x = 0
	if abs(position.x) > x_lim:
		velocity.x = -velocity.x
	if abs(position.z) > z_lim:
		velocity.z = -velocity.z

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if stagger_time > 0.0:
		stagger_time -= delta
	else:
		var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if is_on_floor():
			if direction:
				velocity.x = direction.x * SPEED
				velocity.z = direction.z * SPEED
				if Input.is_action_pressed("speed"):
					velocity *= dash
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)
				velocity.z = move_toward(velocity.z, 0, SPEED)
		
	velocity += knockback
	knockback = Vector3.ZERO

	move_and_slide()
	
	if wall_mode:
		_update_wall_preview()
	if paint_mode:
		_update_paint_highlight()
	elif delete_mode:
		_update_delete_highlight()
	elif highlight_target:
		_clear_highlight()

	
	
# player.gd
@rpc("any_peer", "call_local", "reliable")
func bouncy_bullet(dir: Vector3, power: float) -> void:
	knockback = Vector3(dir.x, 0, dir.z) * power + Vector3.UP * (power * 0.5)
	stagger_time = STAGGER_DURATION

#wall placer
func _enter_wall_mode() -> void:
	delete_mode = false
	paint_mode = false
	wall_mode = true
	wall_edit = 0
	preview_wall = wall_scene.instantiate()
	wall_width = 4.0
	wall_height = 2.5
	wall_thickness = 0.2
	wall_tilt = 0
	wall_angle = 0
	preview_wall.width = wall_width
	preview_wall.height = wall_height
	preview_wall.thickness = wall_thickness
	preview_wall.tilt = wall_tilt
	preview_wall.angle = wall_angle
	# Preview shouldn't block the player or raycasts while being placed.
	preview_wall.collision_layer = 0
	preview_wall.collision_mask = 0
	get_tree().current_scene.add_child(preview_wall)
	# NOT added via RPC - this copy only exists locally for the placer to see.

func _exit_wall_mode() -> void:
	wall_mode = false
	if is_instance_valid(preview_wall):
		preview_wall.queue_free()
	preview_wall = null

func _update_wall_preview() -> void:
	if not is_instance_valid(preview_wall):
		return

	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + camera.global_transform.basis.z * -50.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	var place_pos: Vector3
	if result:
		place_pos = result.position
	else:
		place_pos = from + camera.global_transform.basis.z * -WALL_PLACE_DISTANCE

	preview_wall.global_position = place_pos
	#preview_wall.rotation.y = rotation.y  # face same way as the player
	preview_wall.width = wall_width
	preview_wall.height = wall_height
	preview_wall.thickness = wall_thickness
	preview_wall.tilt = wall_tilt
	preview_wall.rotation.y = wall_angle
	
func _try_place_wall() -> void:
	if not is_instance_valid(preview_wall):
		return
	request_place_wall.rpc_id(1, preview_wall.global_position, preview_wall.rotation.y, wall_width, wall_height, wall_thickness, wall_tilt)
	_exit_wall_mode()

@rpc("any_peer", "call_local", "reliable")
func request_place_wall(pos: Vector3, yaw: float, w: float, h: float, d:float, tilt:float) -> void:
	if not multiplayer.is_server():
		return

	var wall = wall_scene.instantiate()
	wall.name = "Wall_" + str(ResourceUID.create_id())
	wall.global_position = pos
	wall.rotation.y = yaw
	wall.width = w
	wall.height = h
	wall.thickness = d
	wall.tilt = tilt
	get_tree().current_scene.add_child(wall)
	# Set transform/size AFTER adding to the tree, so _ready() has already
	# run and @onready mesh/collision refs exist before _rebuild() fires.
	
func _on_interact_area_body_entered(body: Node) -> void:
	if body.is_in_group("cars"):
		nearby_car = body

func _on_interact_area_body_exited(body: Node) -> void:
	if body == nearby_car:
		nearby_car = null
		
func _on_enter_car(car: Node) -> void:
	current_car = car
	visible = false
	set_physics_process(false)      # stop player movement/gravity entirely
	camera.current = false           # hand off to the car's camera
	collision_layer = 0               # so the player body doesn't block the car/raycasts
	collision_mask = 0

func _on_exit_car(exit_pos: Vector3) -> void:
	global_position = exit_pos
	current_car = null
	visible = true
	set_physics_process(true)
	camera.current = true
	collision_layer = 1
	collision_mask = 1
	
func _try_place_car() -> void:
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + camera.global_transform.basis.z * -50.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	var place_pos: Vector3
	if result:
		place_pos = result.position
	else:
		place_pos = from + camera.global_transform.basis.z * -WALL_PLACE_DISTANCE

	request_place_car.rpc_id(1, place_pos + Vector3.UP * CAR_SPAWN_HEIGHT, rotation.y)

@rpc("any_peer", "call_local", "reliable")
func request_place_car(pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	if get_tree().get_nodes_in_group("cars").size() >= MAX_CARS:
		return

	var car = car_scene.instantiate()
	car.name = "Car_" + str(ResourceUID.create_id())
	get_tree().current_scene.add_child(car)
	# Position is set AFTER add_child: global_position needs the node to be
	# in the tree, and the spawner's initial sync will carry it to clients.
	car.global_position = pos
	car.rotation.y = yaw
	
func _toggle_delete_mode() -> void:
	if delete_mode:
		delete_mode = false
		return
	if wall_mode:
		_exit_wall_mode()
	if paint_mode:
		paint_mode = false
	delete_mode = true
	print("entered delete mode")
	
func _get_target() -> Node:
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * DELETE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if not result:
		return null
	var target = result.collider
	if target is Wall or target.is_in_group("cars"):
		return target
	return null
	
func _try_delete_target() -> void:
	var target := _get_target()
	if target:
		var path := get_tree().current_scene.get_path_to(target)
		request_delete.rpc_id(1, path)

@rpc("any_peer", "call_local", "reliable")
func request_delete(path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var target = get_tree().current_scene.get_node_or_null(path)
	if target == null:
		return
	if not (target is Wall or target.is_in_group("cars")):
		return  # never let a client delete arbitrary nodes
	if target.is_in_group("cars") and target.driver_id != -1:
		return  # don't delete a car someone is driving

	target.queue_free()
	
func _update_delete_highlight() -> void:
	var target := _get_target()
	if target == highlight_target:
		return
	_clear_highlight()
	if target == null:
		return

	if highlight_material == null:
		highlight_material = StandardMaterial3D.new()
		highlight_material.albedo_color = Color(1, 0.1, 0.1, 0.5)
		highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	highlight_target = target
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = highlight_material

func _clear_highlight() -> void:
	if is_instance_valid(highlight_target):
		for mesh in highlight_target.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = null
	highlight_target = null

func _try_paint_target() -> void:
	var target := _get_target()
	if target:
		var path := get_tree().current_scene.get_path_to(target)
		request_paint.rpc_id(1, path, PAINT_COLORS[paint_index])

@rpc("any_peer", "call_local", "reliable")
func request_paint(path: NodePath, color: Color) -> void:
	if not multiplayer.is_server():
		return
	var target = get_tree().current_scene.get_node_or_null(path)
	if target == null or not (target is Wall or target.is_in_group("cars")):
		return
	apply_paint.rpc(path, color)

@rpc("any_peer", "call_local", "reliable")
func apply_paint(path: NodePath, color: Color) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return  # only the server may order this
	var target = get_tree().current_scene.get_node_or_null(path)
	if target == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mat

var paint_highlight_material: StandardMaterial3D
func _update_paint_highlight() -> void:
	if paint_highlight_material == null:
		paint_highlight_material = StandardMaterial3D.new()
		paint_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var c: Color = PAINT_COLORS[paint_index]
	c.a = 0.5
	paint_highlight_material.albedo_color = c   # updates live on existing overlays

	var target := _get_target()
	if target == highlight_target:
		return
	_clear_highlight()
	if target == null:
		return

	highlight_target = target
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = paint_highlight_material
