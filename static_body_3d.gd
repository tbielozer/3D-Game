@tool
extends StaticBody3D
class_name Wall

## Wall dimensions (meters). Change these in the Inspector or via code —
## _rebuild() runs immediately, in-editor and at runtime, so you can see
## the wall without pressing Play.
@export var width: float = 4.0:
	set(value):
		width = value
		_rebuild()

@export var height: float = 2.5:
	set(value):
		height = value
		_rebuild()

@export var thickness: float = 0.2:
	set(value):
		thickness = value
		_rebuild()

@export var material: StandardMaterial3D:
	set(value):
		material = value
		_rebuild()
		
@export var tilt: float = 0:
	set(value):
		rotation.x = value
		_rebuild()
@export var angle: float = 0:
	set(value):
		rotation.y = value
		_rebuild()

# These reference REAL child nodes saved in the scene (see setup below),
# rather than nodes created only at runtime — that's what makes them
# visible in the editor viewport.
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	# Guard: these nodes don't exist until _ready() has run once.
	if not is_node_ready():
		return

	var size := Vector3(width, height, thickness)

	# --- Visual mesh ---
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	if material:
		mesh_instance.material_override = material

	# --- Collision shape ---
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision_shape.shape = box_shape

	# Center the wall on its origin along the vertical axis, same as the mesh,
	# so the node's origin sits at the base-center of the wall.
	mesh_instance.position = Vector3.ZERO
	collision_shape.position = Vector3.ZERO
