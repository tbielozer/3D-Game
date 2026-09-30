extends Node3D

func _ready() -> void:
	$CanvasLayer/VBoxContainer/HostButton.pressed.connect(_on_host_pressed)
	$CanvasLayer/VBoxContainer/HBoxContainer/JoinButton.pressed.connect(_on_join_pressed)

func _on_host_pressed() -> void:
	NetworkManager.host_game()
	$CanvasLayer.visible = false

func _on_join_pressed() -> void:
	# Read whatever the player typed into the IP box.
	var ip_text: String = $CanvasLayer/VBoxContainer/HBoxContainer/IPInput.text

	# Fallback to localhost if they left it blank, so testing solo is still easy.
	if ip_text.strip_edges() == "":
		ip_text = "127.0.0.1"

	NetworkManager.join_game(ip_text)
	$CanvasLayer.visible = false
