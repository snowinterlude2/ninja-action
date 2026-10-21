extends SceneTree
## Writes the game's input actions into project.godot (keyboard and mouse first). Rebind them in
## Project Settings > Input Map; rerunning this tool resets them to these defaults.
##   godot --headless --script res://tools/setup_input.gd

## Action -> keys (physical keycodes) and mouse buttons.
const ACTIONS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"walk": [KEY_ALT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C, KEY_CTRL],
	"debug_menu": [KEY_F1],
	"teleport_1": [KEY_1],
	"teleport_2": [KEY_2],
	"teleport_3": [KEY_3],
	"teleport_4": [KEY_4],
	"teleport_5": [KEY_5],
	"teleport_6": [KEY_6],
	"slow_motion": [KEY_T],
	"reset": [KEY_R],
}


func _init() -> void:
	for action in ACTIONS:
		var events: Array[InputEvent] = []
		for code in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.device = -1
			ev.physical_keycode = code
			events.append(ev)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	print("saved input map: ", error_string(ProjectSettings.save()))
	quit()
