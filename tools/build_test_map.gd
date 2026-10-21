extends SceneTree
## Builds scenes/test_map.tscn: a greybox courtyard with a station for each move, from plain CSG boxes with
## collision and a 1 m grid material. Rerun it after changing the layout here; or edit the saved scene in the
## editor (rerunning overwrites those edits).
##   godot --headless --script res://tools/build_test_map.gd

const OUT := "res://scenes/test_map.tscn"
const GRID := preload("res://shaders/grid.gdshader")
const NINJA := preload("res://scenes/ninja.tscn")
const HUD := preload("res://scripts/debug/debug_hud.gd")
const MENU := preload("res://scripts/ui/game_menu.gd")

const GREY := Color(0.52, 0.53, 0.55)
const WALL := Color(0.62, 0.62, 0.6)
const ORANGE := Color(0.9, 0.55, 0.2)
const BLUE := Color(0.3, 0.5, 0.85)
const TEAL := Color(0.25, 0.7, 0.65)
const PURPLE := Color(0.55, 0.4, 0.8)
const RED := Color(0.8, 0.3, 0.3)
const DARK := Color(0.3, 0.2, 0.2)

var _root: Node3D
var _materials := {}


func _init() -> void:
	_root = Node3D.new()
	_root.name = "TestMap"
	_environment()
	var geo := _group("Geometry")
	_courtyard(geo)
	_vault_lane(_group("1 Vault lane", geo))
	_jump_gaps(_group("2 Jump gaps", geo))
	_wall_run_alley(_group("3 Wall run alley", geo))
	_drop_tower(_group("4-5 Drop tower", geo))
	_tall_wall(_group("6 Wall flip and slopes", geo))
	_slide_bars(_group("7 Slide under", geo))
	_markers()
	var ninja := NINJA.instantiate()
	ninja.name = "Ninja"
	_add(_root, ninja)
	var hud := CanvasLayer.new()
	hud.name = "DebugHud"
	hud.set_script(HUD)
	_add(_root, hud)
	var menu := CanvasLayer.new()
	menu.name = "GameMenu"
	menu.set_script(MENU)
	_add(_root, menu)
	var scene := PackedScene.new()
	scene.pack(_root)
	print("saved %s: %s" % [OUT, error_string(ResourceSaver.save(scene, OUT))])
	_root.free()
	quit()


# --- stations ---

func _courtyard(parent: Node3D) -> void:
	_box(parent, "Floor", Vector3(0, -0.5, 0), Vector3(80, 1, 80), GREY)
	for i in 4:
		var horizontal := i < 2
		var s := 1.0 if i % 2 == 0 else -1.0
		var pos := Vector3(0, 2, 40.5 * s) if horizontal else Vector3(40.5 * s, 2, 0)
		var size := Vector3(82, 4, 1) if horizontal else Vector3(1, 4, 82)
		_box(parent, "Wall%d" % i, pos, size, WALL)
	_box(parent, "SpawnPad", Vector3(0, 0.01, 0), Vector3(3, 0.02, 3), Color(0.85, 0.85, 0.3))


## Obstacles in a row, low to high, so you can chain them at a sprint.
func _vault_lane(parent: Node3D) -> void:
	var x := -14.0
	_label(parent, "1  VAULT LANE", Vector3(x, 3, -6))
	# [z, height, depth]
	var obstacles := [[-10.0, 0.6, 0.4], [-15.0, 0.9, 0.5], [-20.0, 1.0, 0.8], [-25.0, 1.5, 0.4], [-30.0, 1.1, 1.2]]
	for i in obstacles.size():
		var o: Array = obstacles[i]
		_box(parent, "Vault%d_%dcm" % [i + 1, int(o[1] * 100)], Vector3(x, o[1] * 0.5, o[0]), Vector3(3, o[1], o[2]), ORANGE)
		_label(parent, "%.1f m" % o[1], Vector3(x + 2, o[1] + 0.4, o[0]), 0.5)


## Up the ramp onto 2 m platforms, then gaps of 2, 3.5 and 5 m.
func _jump_gaps(parent: Node3D) -> void:
	var x := 14.0
	_label(parent, "2  JUMP GAPS", Vector3(x, 4, -4))
	_ramp(parent, "Ramp", Vector3(x, 0, -4), 6.0, 2.0, 3.0, BLUE)
	# [start z, length, gap label]
	var platforms := [[-10.0, 4.0, ""], [-16.0, 3.0, "2 m"], [-22.5, 3.0, "3.5 m"], [-30.5, 4.0, "5 m"]]
	for i in platforms.size():
		var p: Array = platforms[i]
		_box(parent, "Platform%d" % (i + 1), Vector3(x, 1.0, p[0] - p[1] * 0.5), Vector3(3, 2, p[1]), BLUE)
		if p[2] != "":
			_label(parent, "gap " + p[2], Vector3(x, 3.0, p[0] + 0.8), 0.6)


## Two long parallel walls to wall run and kick back and forth between, and one wall between two ledges with
## a "don't touch" floor, so you have to wall run across.
func _wall_run_alley(parent: Node3D) -> void:
	_label(parent, "3  WALL RUN ALLEY", Vector3(0, 7, 8))
	_box(parent, "AlleyWallL", Vector3(-2.25, 3, 21), Vector3(0.5, 6, 22), TEAL)
	_box(parent, "AlleyWallR", Vector3(2.25, 3, 21), Vector3(0.5, 6, 22), TEAL)
	var x := -10.0
	_label(parent, "3b  WALL RUN ACROSS", Vector3(x, 6, 10))
	_box(parent, "LedgeStart", Vector3(x, 0.75, 11.5), Vector3(3, 1.5, 3), TEAL)
	_box(parent, "LedgeEnd", Vector3(x, 0.75, 26.5), Vector3(3, 1.5, 3), TEAL)
	_box(parent, "RunWall", Vector3(x - 1.75, 3, 19), Vector3(0.5, 6, 18), TEAL)
	_box(parent, "NoTouchFloor", Vector3(x, 0.01, 19), Vector3(3, 0.02, 12), DARK)


## Pillars 3, 6, 10 and 16 m tall side by side, to test soft landings, rolls and hard landings.
func _drop_tower(parent: Node3D) -> void:
	_label(parent, "4-5  DROP TOWER", Vector3(24, 18, 12))
	var heights := [3.0, 6.0, 10.0, 16.0]
	for i in heights.size():
		var h: float = heights[i]
		var x := 18.0 + i * 4.0
		_box(parent, "Pillar_%dm" % int(h), Vector3(x, h * 0.5, 18), Vector3(3, h, 3), PURPLE)
		_label(parent, "%d m" % int(h), Vector3(x, h + 0.6, 16.4), 0.6)


## A 6 m wall to run up and flip off, and ramps to test walking on slopes.
func _tall_wall(parent: Node3D) -> void:
	_label(parent, "6  WALL FLIP", Vector3(-26, 7, 18))
	_box(parent, "TallWall", Vector3(-27, 3, 18), Vector3(1, 6, 8), RED)
	_ramp(parent, "Slope20", Vector3(-24, 0, -6), 6.0, 2.2, 4.0, GREY)
	_ramp(parent, "Slope35", Vector3(-30, 0, -6), 5.0, 3.5, 4.0, GREY)
	_label(parent, "slopes 20° / 35°", Vector3(-27, 4.5, -8), 0.6)


## Bars at waist height to slide under (sprint, then C), one low and one long.
func _slide_bars(parent: Node3D) -> void:
	var x := 0.0
	_label(parent, "7  SLIDE UNDER", Vector3(x, 3, -8))
	# [z, bottom height, depth]
	var bars := [[-12.0, 1.0, 0.3], [-18.0, 0.95, 0.3], [-24.0, 1.0, 2.0]]
	for i in bars.size():
		var b: Array = bars[i]
		_box(parent, "SlideBar%d" % (i + 1), Vector3(x, b[1] + 0.25, b[0]), Vector3(3, 0.5, b[2]), ORANGE)
		_box(parent, "SlidePostL%d" % (i + 1), Vector3(x - 1.6, (b[1] + 0.5) * 0.5, b[0]), Vector3(0.2, b[1] + 0.5, 0.2), WALL)
		_box(parent, "SlidePostR%d" % (i + 1), Vector3(x + 1.6, (b[1] + 0.5) * 0.5, b[0]), Vector3(0.2, b[1] + 0.5, 0.2), WALL)


func _markers() -> void:
	var markers := _group("Teleports")
	_marker(markers, "Spawn", Vector3(0, 0.1, 0), 0.0)
	_marker(markers, "Station1", Vector3(-14, 0.1, -4), 0.0)
	_marker(markers, "Station2", Vector3(14, 0.1, -1), 0.0)
	_marker(markers, "Station3", Vector3(0, 0.1, 5), PI)
	_marker(markers, "Station4", Vector3(22, 6.1, 18), PI)
	_marker(markers, "Station5", Vector3(30, 16.1, 18), PI)
	_marker(markers, "Station6", Vector3(-17, 0.1, 18), PI * 0.5)
	_marker(markers, "Station7", Vector3(0, 0.1, -4), 0.0)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	_add(_root, world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	_add(_root, sun)


# --- building blocks ---

func _box(parent: Node, box_name: String, pos: Vector3, size: Vector3, color: Color) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = box_name
	b.position = pos
	b.size = size
	b.use_collision = true
	b.collision_layer = 1
	b.material = _material(color)
	_add(parent, b)
	return b


## A ramp `length` meters long (along -Z from `start`) rising `rise` meters.
func _ramp(parent: Node, ramp_name: String, start: Vector3, length: float, rise: float, width: float, color: Color) -> void:
	var angle := atan2(rise, length)
	var slope := sqrt(length * length + rise * rise)
	var thick := 0.4
	var b := _box(parent, ramp_name, Vector3.ZERO, Vector3(width, thick, slope), color)
	b.rotation.x = angle
	# put the top surface's ends on the ground at `start` and at the rise
	var mid := start + Vector3(0, rise * 0.5, -length * 0.5)
	b.position = mid - Vector3(0, cos(angle), sin(angle)) * thick * 0.5


func _label(parent: Node, text: String, pos: Vector3, size := 1.0) -> void:
	var l := Label3D.new()
	l.name = "Label_" + text.validate_node_name().replace(" ", "_")
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.01 * size
	l.font_size = 64
	l.outline_size = 12
	_add(parent, l)


func _marker(parent: Node, marker_name: String, pos: Vector3, yaw: float) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	m.rotation.y = yaw
	_add(parent, m)


func _group(group_name: String, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	_add(parent if parent else _root, n)
	return n


func _material(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var m := ShaderMaterial.new()
		m.shader = GRID
		m.set_shader_parameter("albedo", color)
		_materials[color] = m
	return _materials[color]


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root
