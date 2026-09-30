@tool
extends StaticBody3D
class_name Terrain

## Procedural terrain: displaces a subdivided plane using FastNoiseLite,
## then builds a matching HeightMapShape3D for collision.
## Setup: add a MeshInstance3D child named "MeshInstance3D" and a
## CollisionShape3D child named "CollisionShape3D" under this node, save
## the scene, then tweak the exports below — @tool makes it regenerate
## live in the editor.

## World-space size of the terrain along X and Z.
@export var size: Vector2 = Vector2(50, 50):
	set(value):
		size = value
		_generate()

## Number of quads along each axis. Higher = smoother but heavier.
## Vertex grid is (resolution + 1) x (resolution + 1).
@export_range(2, 256, 1) var resolution: int = 64:
	set(value):
		resolution = value
		_generate()

## Max height displacement in world units.
@export var height_scale: float = 8.0:
	set(value):
		height_scale = value
		_generate()

@export var noise: FastNoiseLite:
	set(value):
		noise = value
		_connect_noise()
		_generate()

@export var material: StandardMaterial3D:
	set(value):
		material = value
		_generate()

## Rebuild collision every time (can be slow on very high resolutions).
## Turn off while iterating on visuals, then re-enable for the final pass.
@export var generate_collision: bool = true:
	set(value):
		generate_collision = value
		_generate()

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Cached heights so collision build doesn't need to re-sample noise.
var _heights: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	if not noise:
		noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.frequency = 0.03
		noise.fractal_octaves = 4
	_connect_noise()
	_generate()

func _connect_noise() -> void:
	if noise and not noise.changed.is_connected(_generate):
		noise.changed.connect(_generate)

func _generate() -> void:
	if not is_node_ready() or not noise:
		return

	var verts_x := resolution + 1
	var verts_z := resolution + 1
	_heights.resize(verts_x * verts_z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step_x := size.x / resolution
	var step_z := size.y / resolution
	var origin := Vector3(-size.x * 0.5, 0.0, -size.y * 0.5)

	# --- Pass 1: sample all heights first, so normals (pass 2) can look
	# at neighboring samples regardless of the order we visit them in ---
	for z in verts_z:
		for x in verts_x:
			var world_x := origin.x + x * step_x
			var world_z := origin.z + z * step_z
			_heights[z * verts_x + x] = noise.get_noise_2d(world_x, world_z) * height_scale

	# --- Pass 2: add vertices with explicit, slope-based normals ---
	# Computed straight from the heightmap (central differences) rather than
	# left to generate_normals(), so the "up" direction is unambiguous and
	# doesn't depend on triangle winding at all.
	for z in verts_z:
		for x in verts_x:
			var world_x := origin.x + x * step_x
			var world_z := origin.z + z * step_z
			var h := _heights[z * verts_x + x]

			var h_left := _heights[z * verts_x + max(x - 1, 0)]
			var h_right := _heights[z * verts_x + min(x + 1, verts_x - 1)]
			var h_down := _heights[max(z - 1, 0) * verts_x + x]
			var h_up := _heights[min(z + 1, verts_z - 1) * verts_x + x]

			var normal := Vector3(
				(h_left - h_right) / (2.0 * step_x),
				1.0,
				(h_down - h_up) / (2.0 * step_z)
			).normalized()

			var uv := Vector2(float(x) / resolution, float(z) / resolution)
			st.set_normal(normal)
			st.set_uv(uv)
			st.add_vertex(Vector3(world_x, h, world_z))

	# --- Build triangle indices ---
	# Winding no longer matters for visibility (culling is disabled below)
	# or for lighting (normals are set explicitly above).
	for z in resolution:
		for x in resolution:
			var i0 := z * verts_x + x
			var i1 := i0 + 1
			var i2 := i0 + verts_x
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)

	st.generate_tangents()

	mesh_instance.mesh = st.commit()
	if material:
		# Disabled so the terrain always renders top and bottom, regardless
		# of triangle winding — removes this whole class of bug.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = material

	if generate_collision:
		_build_collision(verts_x, verts_z)

func _build_collision(verts_x: int, verts_z: int) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = verts_x
	shape.map_depth = verts_z
	shape.map_data = _heights
	collision_shape.shape = shape

	# HeightMapShape3D assumes 1-unit spacing between samples, so scale the
	# CollisionShape3D node itself to stretch it to the mesh's real size.
	collision_shape.scale = Vector3(size.x / resolution, 1.0, size.y / resolution)
	collision_shape.position = Vector3.ZERO

## Returns the world-space height at the given XZ position (nearest sample,
## no interpolation). Useful for placing objects on the terrain at runtime.
func get_height_at(world_x: float, world_z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var verts_x := resolution + 1
	var origin := Vector3(-size.x * 0.5, 0.0, -size.y * 0.5)
	var gx := int(round((world_x - origin.x) / (size.x / resolution)))
	var gz := int(round((world_z - origin.z) / (size.y / resolution)))
	gx = clamp(gx, 0, verts_x - 1)
	gz = clamp(gz, 0, resolution)
	return _heights[gz * verts_x + gx]
