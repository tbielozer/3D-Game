extends Node

# --- Config ---
const PORT = 7777              # Arbitrary port number both host and clients agree on
const MAX_PLAYERS = 4

var player_scene = preload("res://player.tscn")
# NOTE: update this path to match wherever your Player scene actually lives.

@onready var spawner: MultiplayerSpawner = $"/root/Main/MultiplayerSpawner"
# NOTE: update this path to match wherever you place the MultiplayerSpawner node
# in your actual scene tree.

@export var spawn_origin: Vector3 = Vector3.ZERO
# Set this in the Inspector to wherever your floor actually sits, so spawned
# players land in the right spot instead of a hardcoded world origin.
@export var spawn_spacing: float = 2.0
# Distance between each player's spawn point, so they don't overlap.


func host_game() -> void:
	var peer = ENetMultiplayerPeer.new()
	# create_server(port, max_clients) - starts listening for connections on this port.
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		print("Failed to host: ", error)
		return

	multiplayer.multiplayer_peer = peer
	print("Hosting on port ", PORT)

	# The host is also "peer 1" and needs their own player spawned too.
	_spawn_player(multiplayer.get_unique_id())

	# Whenever a NEW client connects later, spawn a player for them too.
	# (MultiplayerSpawner then replicates that spawn to every already-connected
	# peer, AND to the new peer as part of their initial sync.)
	multiplayer.peer_connected.connect(_spawn_player)
	
	await get_tree().process_frame

	var terrain := get_tree().current_scene.get_node("StaticBody3D2") as Terrain
	terrain.spawn_objects()


func join_game(ip_address: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	# create_client(address, port) - connects out to a hosting peer.
	var error = peer.create_client(ip_address, PORT)
	if error != OK:
		print("Failed to connect: ", error)
		return

	multiplayer.multiplayer_peer = peer
	print("Connecting to ", ip_address, "...")


func _spawn_player(id: int) -> void:
	# IMPORTANT: this should only ever be called on the SERVER/host.
	# The MultiplayerSpawner watches the spawn path we configured in the editor,
	# and automatically replicates "a new child appeared here" to every client -
	# so we only need to add_child() once, on the authority, and everyone else
	# gets a matching copy created for them automatically.
	if not multiplayer.is_server():
		return

	var player = player_scene.instantiate()

	player.name = str(id)
	# Naming the node after the peer's unique ID lets us find/reference it later,
	# and is required for MultiplayerSynchronizer to know which peer owns it.

	# Assigns which peer is allowed to control this player instance.
	# Only the matching peer's is_multiplayer_authority() will return true.
	player.set_multiplayer_authority(id)

	get_tree().current_scene.add_child(player)

	# Space out spawn points so players don't land stacked on top of each
	# other (which can shove them off a small floor via collision push-out).
	# Simple approach: offset along X based on how many players exist so far.
	var player_count := get_tree().get_nodes_in_group("players").size()
	player.add_to_group("players")
	player.global_position = spawn_origin + Vector3(player_count * spawn_spacing, 2.0, 0)
	# Offsets each player along X from your chosen spawn_origin, and drops them
	# 2 units above it so they fall a short distance onto the floor rather than
	# potentially spawning exactly at/inside it.
