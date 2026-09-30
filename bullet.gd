extends RigidBody3D

const SPEED = 20.0
const LIFETIME = 3.0        # Slightly longer than before, since bouncing bullets
							 # travel further/longer before settling or leaving the level
const MAX_BOUNCES = 3        # Optional: destroy after this many bounces so it
							 # doesn't ricochet around forever

var direction: Vector3 = Vector3.FORWARD
var bounce_count: int = 0

@export var bullet_power = 5

func _ready() -> void:
	# Only the SERVER simulates and owns bullet physics - clients just see
	# the replicated position via MultiplayerSynchronizer, same as before.
	if not multiplayer.is_server():
		# Turn off physics simulation entirely on clients, so their local
		# physics engine doesn't try to independently (and differently)
		# simulate bouncing - that would desync from what the server shows.
		freeze = true
		set_physics_process(false)
		return

	# Give the bullet its initial velocity. Unlike Area3D (where we moved
	# global_position manually every frame), RigidBody3D wants velocity set
	# ONCE, and the physics engine moves and bounces it automatically from
	# then on - no per-frame movement code needed at all.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	linear_velocity = direction * SPEED

	# Auto-delete after LIFETIME seconds if it's still bouncing around.
	await get_tree().create_timer(LIFETIME).timeout
	if is_instance_valid(self):
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	# Requires: this node's "Contact Monitor" property set to ON, and
	# "Max Contacts Reported" set to at least 1 (both in the Inspector,
	# under the RigidBody3D section) - otherwise this signal never fires.
	if not multiplayer.is_server():
		return
	if body.is_in_group("players"):
		if body.has_method("bouncy_bullet"):
			print("Player hit")
			var push_dir = (body.global_position - global_position)
			push_dir.y = 0
			#var current_dir = linear_velocity.normalized() if linear_velocity.length() > 0.01 else Vector3.FORWARD
			push_dir = push_dir.normalized() if push_dir.length() > 0.01 else Vector3.FORWARD
			body.rpc_id(body.name.to_int(), "bouncy_bullet", push_dir, bullet_power)
			
	#Hit something else (wall, floor, etc.) - let it bounce instead of
	# destroying immediately.
	#bounce_count += 1
	#if bounce_count >= MAX_BOUNCES:
		#queue_free()
		
