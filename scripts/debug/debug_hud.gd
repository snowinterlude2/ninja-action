extends CanvasLayer
## Test-map helpers: F1 shows or hides this panel, 1-6 teleport to the stations, T toggles slow motion,
## R puts the ninja back on the spawn pad.

const HELP := """WASD move   Mouse look   Shift sprint   Alt walk
Space jump / vault / wall run kick-off / wall flip
C or Ctrl  roll, slide (when sprinting), roll on landing (press just before)
Wall run: sprint + jump along a wall.  Space during it jumps off.

1-6 teleport to stations   T slow motion   R reset   F1 hide this   Esc free mouse"""

var _ninja: Ninja
var _label: Label
var _slow := false


func _ready() -> void:
	_ninja = get_tree().get_first_node_in_group("player")
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_label)


func _process(_delta: float) -> void:
	if not visible or _ninja == null:
		return
	var v := _ninja.velocity
	_label.text = "%s\nstate: %s   clip: %s\nspeed: %.1f m/s   vertical: %.1f   last drop: %.1f m%s" % [
		HELP, _ninja.state_name(), _ninja.current_clip, Vector2(v.x, v.z).length(), v.y, _ninja.last_drop,
		"   SLOW MOTION" if _slow else ""]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		visible = not visible
	elif event.is_action_pressed("slow_motion"):
		_slow = not _slow
		Engine.time_scale = 0.25 if _slow else 1.0
	elif event.is_action_pressed("reset"):
		_teleport("Spawn")
	else:
		for i in range(1, 7):
			if event.is_action_pressed("teleport_%d" % i):
				_teleport("Station%d" % i)


func _teleport(marker_name: String) -> void:
	var marker := get_tree().current_scene.find_child(marker_name, true, false) as Node3D
	if marker and _ninja:
		_ninja.teleport(marker.global_transform)
