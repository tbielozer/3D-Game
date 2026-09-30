extends CanvasLayer

@onready var ActionsBox: HBoxContainer = $UpperHUD/HBoxContainer2/HBoxContainer
@onready var SpecialLabel: Label = $UpperHUD/HBoxContainer2/Label

var parent

#wall_edit
#0 = width, 1 = height, 2 = thickness, 3 = tilt, 4- angle
const WALL_EDIT = ["WIDTH", "HEIGHT", "DEPTH", "TILT", "ANGLE"]
const PAINT_COLORS = ["RED", "ORANGE", "YELLOW", "GREEN", "CYAN", "BLUE", "MAGENTA", "WHITE", "BLACK"]


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	parent = get_parent()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if parent.is_in_group("players"):
		ActionsBox.get_node("Action1").modulate = Color.GREEN if parent.delete_mode else Color.WHITE
		ActionsBox.get_node("Action2").modulate = Color.GREEN if parent.wall_mode else Color.WHITE
		ActionsBox.get_node("Action4").modulate = Color.GREEN if parent.paint_mode else Color.WHITE
		if parent.delete_mode:
			SpecialLabel.text = "Click to Delete"
		elif parent.wall_mode:
			SpecialLabel.text = WALL_EDIT[parent.wall_edit]
		elif parent.paint_mode:
			SpecialLabel.text = PAINT_COLORS[parent.paint_index]
		elif parent.nearby_car:
			SpecialLabel.text = "Press 'E' to Enter"
		else:
			SpecialLabel.text = ""
			
	pass
