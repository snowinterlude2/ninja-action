extends CanvasLayer
## The game menu, in a Windows XP (Luna) style window: shown at the start and on Esc. Pauses the game while open.
## Also plays the music on a loop.

const MUSIC := preload("res://assets/music/maze_fortress.ogg")

const XP_BLUE := Color(0.0, 0.33, 0.89)
const XP_BLUE_LIGHT := Color(0.24, 0.55, 0.98)
const XP_FACE := Color(0.93, 0.91, 0.85)
const XP_EDGE := Color(0.0, 0.2, 0.6)
const XP_BUTTON := Color(0.96, 0.96, 0.94)
const XP_BUTTON_EDGE := Color(0.0, 0.24, 0.45)
const XP_HOVER := Color(0.99, 0.82, 0.45)

var _music: AudioStreamPlayer
var _window: PanelContainer
var _play_button: Button
var _camera_button: Button
var _music_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var song: AudioStreamOggVorbis = MUSIC
	song.loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = song
	_music.volume_db = -10.0
	add_child(_music)
	_music.play()
	_build()
	# headless test runs skip the start menu
	if DisplayServer.get_name() == "headless":
		_close()
	else:
		# let the camera settle behind him first, or the paused game shows it inside his head
		_window.visible = false
		await get_tree().create_timer(0.3).timeout
		_open("Play")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _window.visible:
			_close()
		else:
			_open("Resume")
		get_viewport().set_input_as_handled()


func _open(play_text: String) -> void:
	_play_button.text = play_text
	_refresh()
	_window.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	_window.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _camera_rig() -> Node:
	var ninja := get_tree().get_first_node_in_group("player")
	return ninja.get_node_or_null("CameraRig") if ninja else null


func _refresh() -> void:
	var rig := _camera_rig()
	_camera_button.text = "Camera: %s  (V)" % ("Over the shoulder" if rig and rig.shoulder else "Wide")
	_music_button.text = "Music: %s" % ("On" if _music.playing else "Off")


# --- the XP window ---

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", _box(XP_FACE, XP_EDGE, 3, [8, 8, 0, 0]))
	_window.custom_minimum_size = Vector2(340, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_window.add_child(column)
	# title bar
	var bar := PanelContainer.new()
	var bar_style := _box(XP_BLUE, XP_BLUE, 0, [6, 6, 0, 0])
	bar_style.content_margin_left = 8
	bar_style.content_margin_top = 4
	bar_style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", bar_style)
	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Ninja Action"
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0.3, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(24, 22)
	close.add_theme_stylebox_override("normal", _box(Color(0.85, 0.3, 0.2), Color.WHITE, 1, [3, 3, 3, 3]))
	close.add_theme_stylebox_override("hover", _box(Color(0.95, 0.45, 0.3), Color.WHITE, 1, [3, 3, 3, 3]))
	close.add_theme_stylebox_override("pressed", _box(Color(0.7, 0.2, 0.1), Color.WHITE, 1, [3, 3, 3, 3]))
	close.add_theme_color_override("font_color", Color.WHITE)
	close.pressed.connect(_close)
	title_row.add_child(close)
	bar.add_child(title_row)
	column.add_child(bar)
	# body
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 16)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	body.add_child(buttons)
	column.add_child(body)
	_play_button = _button(buttons, "Play", _close)
	_camera_button = _button(buttons, "Camera", func() -> void:
		var rig := _camera_rig()
		if rig:
			rig.shoulder = not rig.shoulder
		_refresh())
	_music_button = _button(buttons, "Music", func() -> void:
		if _music.playing:
			_music.stop()
		else:
			_music.play()
		_refresh())
	var volume_row := HBoxContainer.new()
	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_label.add_theme_color_override("font_color", Color.BLACK)
	volume_label.custom_minimum_size.x = 70
	volume_row.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = -40.0
	volume.max_value = 0.0
	volume.value = AudioServer.get_bus_volume_db(0)
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume.value_changed.connect(func(v: float) -> void: AudioServer.set_bus_volume_db(0, v))
	volume_row.add_child(volume)
	buttons.add_child(volume_row)
	var help := Label.new()
	help.text = "WASD move · Shift sprint · Space jump/vault/climb\nC roll (slide at a sprint) · V camera · Esc menu"
	help.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))
	help.add_theme_font_size_override("font_size", 12)
	buttons.add_child(help)
	_button(buttons, "Quit", func() -> void: get_tree().quit())
	center.add_child(_window)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	root.add_child(center)
	add_child(root)
	_window.visibility_changed.connect(func() -> void: dim.visible = _window.visible)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_stylebox_override("normal", _box(XP_BUTTON, XP_BUTTON_EDGE, 1, [3, 3, 3, 3]))
	b.add_theme_stylebox_override("hover", _box(XP_BUTTON, XP_HOVER, 2, [3, 3, 3, 3]))
	b.add_theme_stylebox_override("pressed", _box(Color(0.88, 0.87, 0.82), XP_BUTTON_EDGE, 1, [3, 3, 3, 3]))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), XP_BLUE_LIGHT, 1, [3, 3, 3, 3]))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color.BLACK)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _box(fill: Color, edge: Color, width: int, corners: Array) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(width)
	s.corner_radius_top_left = corners[0]
	s.corner_radius_top_right = corners[1]
	s.corner_radius_bottom_right = corners[2]
	s.corner_radius_bottom_left = corners[3]
	s.content_margin_left = 6
	s.content_margin_right = 6
	return s
