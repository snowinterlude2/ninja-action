class_name NinjaSfx
extends Node3D
## The ninja's sounds: footsteps timed to the run and walk loops, and one-shots (jump, land, whoosh, impact) and
## voice (grunts, pain) that the controller asks for. Each kind has a few takes and picks one at random.

const DIR := "res://assets/sounds/"
const SETS := {
	"step_run": ["step_run_1", "step_run_2", "step_run_3", "step_run_4", "step_run_5"],
	"step_walk": ["step_walk_1", "step_walk_2", "step_walk_3"],
	"jump": ["jump"],
	"land": ["land"],
	"whoosh": ["whoosh_1", "whoosh_2", "whoosh_3"],
	"impact": ["impact_1", "impact_2"],
	"pain": ["pain_1", "pain_2", "pain_6", "pain_9"],
	"pain_big": ["pain_big_2", "pain_big_5"],
}
## Loop clip -> where in the loop (0 to 1) each foot hits the ground.
const STEPS := {
	"walk": [0.0, 0.5],
	"run": [0.0, 0.5],
	"sprint": [0.0, 0.5],
	"wall_run": [0.0, 0.5],
	"wall_run_mirror": [0.0, 0.5],
	"wall_up": [0.0],
}

var _streams := {}
var _fx: Array[AudioStreamPlayer3D] = []
var _voice: AudioStreamPlayer3D
var _feet: AudioStreamPlayer3D
var _next_fx := 0
var _last_phase := 0.0
var _last_clip := ""


func _ready() -> void:
	for key in SETS:
		var list: Array[AudioStream] = []
		for f in SETS[key]:
			list.append(load(DIR + f + ".ogg"))
		_streams[key] = list
	for i in 3:
		_fx.append(_player(0.0))
	_voice = _player(-2.0)
	_feet = _player(-10.0)
	position.y = 1.0


func _player(db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db = db
	p.unit_size = 6.0
	add_child(p)
	return p


## A one-shot on the next free effects channel.
func play(kind: String, db := 0.0) -> void:
	var p := _fx[_next_fx]
	_next_fx = (_next_fx + 1) % _fx.size()
	_start(p, kind, db)


## Pain cries, one at a time (a new one cuts the last).
func voice(kind: String, db := 0.0) -> void:
	_start(_voice, kind, db - 2.0)


func _start(p: AudioStreamPlayer3D, kind: String, db: float) -> void:
	p.stream = (_streams[kind] as Array).pick_random()
	p.volume_db = db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


## Called every physics frame: a step sound each time the playing loop passes a foot's contact.
func footsteps(ninja: Ninja) -> void:
	var anim: AnimationPlayer = ninja.get_node("Model/AnimationPlayer")
	var clip := ninja.current_clip
	if not STEPS.has(clip) or not anim.is_playing() or anim.current_animation_length <= 0.0:
		_last_clip = ""
		return
	var phase := fposmod(anim.current_animation_position / anim.current_animation_length, 1.0)
	if clip == _last_clip:
		for hit in STEPS[clip]:
			var crossed: bool = (_last_phase < hit and phase >= hit) if phase >= _last_phase \
					else (hit > _last_phase or phase >= hit)
			if crossed:
				_start(_feet, "step_walk" if clip == "walk" else "step_run", -12.0 if clip == "walk" else -8.0)
	_last_clip = clip
	_last_phase = phase
