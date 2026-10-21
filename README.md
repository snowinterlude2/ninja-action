# Ninja Action

Third-person ninja locomotion game in Godot 4.7 (Jolt physics). Open the folder in Godot 4.7 and press F5:
you start on the yellow pad in the middle of the greybox test map.

## Controls

| Action | Keys |
|---|---|
| Move / look | W A S D / mouse |
| Sprint / walk | hold Shift / hold Alt |
| Jump, vault, wall flip | Space (does what fits: vault in front of a low obstacle, run up a tall wall, else jump) |
| Wall run | sprint and jump along a wall; Space during it kicks off to the other side |
| Roll / slide | C or Ctrl (slide when sprinting); press it just before landing to roll out of a big fall |
| Test helpers | 1-6 teleport to stations, R back to spawn, T slow motion, F1 hide the help panel, Esc free the mouse |

All keys are actions in Project Settings > Input Map, so they can be rebound.

## Test map stations

1. Vault lane: 0.6, 0.9, 1.0, 1.5 (climb over) and 1.1 m (too deep, jump onto it) obstacles in a row.
2. Jump gaps: up the ramp, then gaps of 2, 3.5 and 5 m.
3. Wall run alley: two parallel walls to run and kick between, and (3b) one wall between two ledges.
4. / 5. Drop tower: pillars of 3, 6, 10 and 16 m. Under 4 m you just land; above it you take a hard landing
   unless you roll (C just before you touch down).
6. A 6 m wall to run up and flip off, and 20° and 35° slopes.

## How it's built

- `scripts/player/ninja.gd`: the controller. A CharacterBody3D with states GROUND, AIR, WALL_RUN and ACTION.
  One-shot moves (vault, roll, slide, landings, wall flip) are driven by the clip's root motion, stretched to fit
  the obstacle. Every tuning value is an export on the Ninja node.
- `scripts/player/camera_rig.gd`: orbit camera on a SpringArm3D.
- `assets/animations/ninja_locomotion.res`: all clips in one AnimationLibrary, baked from the Mixamo FBX files in
  `assets/animations/source/`.

## Tools

Run from the project folder (`godot` is the Godot 4.7 binary):

| Tool | What it does |
|---|---|
| `godot --headless --script res://tools/bake_animations.gd` | Rebakes the animation library. Edit `CLIPS` to add a clip, `MIRRORED` to get a flipped copy. |
| `godot --headless --script res://tools/build_test_map.gd` | Rebuilds `scenes/test_map.tscn` from code. |
| `godot --headless --fixed-fps 60 --script res://tools/test_moves.gd` | Plays the map with scripted keys and checks each move (run, vault, climb over, wall run and kick, landings, slide, wall flip). |
| `godot --headless --script res://tools/test_mirror.gd` | Checks the mirror: the flipped left strafe must match the real right strafe. |
| `godot --headless --script res://tools/inspect_clips.gd` | Lists every source clip's length and how far its hips travel. |
| `godot --headless --script res://tools/setup_input.gd` | Resets the input map to the defaults above. |
| `xvfb-run godot --rendering-driver opengl3 --script res://tools/screenshots.gd -- <dir>` | Saves posed screenshots around the map. |
