extends Node2D

const COLS := 10
const ROWS := 20
const CELL := 30
const BOARD_POS := Vector2(20, 20)
const PANEL_X := 350.0
const BASE_SIZE := Vector2(560, 640)  # layout size; matches the project's viewport size

const DAS := 0.17          # delay before auto-repeat when holding left/right
const ARR := 0.05          # auto-repeat rate
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const LINE_SCORES := [0, 100, 300, 500, 800]
const KICKS := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(1, -1)]

var SHAPES := {
	"I": {"n": 4, "color": Color("3ee0ff"), "cells": [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]},
	"O": {"n": 2, "color": Color("ffd93b"), "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
	"T": {"n": 3, "color": Color("b35cff"), "cells": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]},
	"S": {"n": 3, "color": Color("5cec6b"), "cells": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]},
	"Z": {"n": 3, "color": Color("ff4f8b"), "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]},
	"J": {"n": 3, "color": Color("4f7dff"), "cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]},
	"L": {"n": 3, "color": Color("ff8a3d"), "cells": [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]},
}

var grid: Array = []
var next_queue: Array = []
var cur_type := ""
var cur_rot := 0
var cur_pos := Vector2i.ZERO
var hold_type := ""
var hold_used := false

var score := 0
var lines := 0
var level := 1
var game_over := false
var paused := false

const TITLE := "BLOCK DROP"
const SAVE_PATH := "user://save.cfg"
const MAX_START_LEVEL := 15

var screen := "menu"        # "menu" (title screen) or "game"
var menu_sel := 0
var start_level := 1
var best := 0
var new_best := false
var menu_time := 0.0
var menu_decor: Array = []  # pieces drifting down behind the title screen
var stick_prev := {}        # last value of each gamepad stick axis, for menu navigation

var fall_timer := 0.0
var lock_timer := 0.0
var lock_resets := 0
var das_dir := 0
var das_timer := 0.0
var arr_timer := 0.0
const SHARDS_PER_SIDE := 3   # each cleared block breaks into 3x3 fragments
const PARTICLE_GRAVITY := 900.0

var particles: Array = []

var font: Font

# ---------------------------------------------------------------- sound
# All effects are synthesized at startup: each is a list of [start_hz, end_hz, seconds]
# segments played back to back with a chosen waveform.

const SAMPLE_RATE := 22050
const VOICES := 8

var sounds := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0


func build_sounds() -> void:
	var C5 := 523.25
	var E5 := 659.25
	var G5 := 783.99
	var C6 := 1046.5
	var E6 := 1318.5
	var G6 := 1568.0
	sounds = {
		# Soft wooden "tok": left and right are a step apart in pitch
		"move_left": synth("marimba", [[G5, G5, 0.09]], 0.16, 4.0),
		"move_right": synth("marimba", [[880.0, 880.0, 0.09]], 0.16, 4.0),
		"rotate": synth("triangle", [[520, 900, 0.06]], 0.30),
		# Soft "thock": low body thump, a woody knock, and a muffled contact click
		"lock": to_stream(layer([
			tone("sine", [[150, 55, 0.14]], 0.50, 3.0),
			tone("marimba", [[330, 330, 0.12]], 0.10, 5.0),
			tone("noise", [[0, 0, 0.03]], 0.12, 6.0),
		])),
		# Heavier landing: deeper thump and click with a faint chime ringing on top
		"drop": to_stream(layer([
			tone("sine", [[170, 42, 0.24]], 0.60, 2.5),
			tone("marimba", [[262, 262, 0.16]], 0.12, 5.0),
			tone("noise", [[0, 0, 0.05]], 0.18, 5.0),
			tone("marimba", [[C5, C5, 0.40]], 0.07, 3.5),
			tone("marimba", [[G5, G5, 0.40]], 0.04, 3.5),
		])),
		"hold": synth("sine", [[350, 750, 0.09]], 0.35),
		"pause": synth("sine", [[660, 660, 0.06], [880, 880, 0.06]], 0.30),
		"clear1": synth("square", [[C5, C5, 0.06], [G5, G5, 0.10]], 0.14),
		"clear2": synth("square", [[C5, C5, 0.06], [E5, E5, 0.06], [G5, G5, 0.12]], 0.14),
		"clear3": synth("square", [[C5, C5, 0.05], [E5, E5, 0.05], [G5, G5, 0.05], [C6, C6, 0.14]], 0.14),
		"clear4": synth("square", [[C5, C5, 0.05], [E5, E5, 0.05], [G5, G5, 0.05], [C6, C6, 0.05], [E6, E6, 0.05], [G6, G6, 0.25]], 0.15),
		"levelup": synth("triangle", [[G5, G5, 0.08], [C6, C6, 0.08], [E6, E6, 0.08], [G6, G6, 0.08], [C6 * 2, C6 * 2, 0.25]], 0.30),
		"gameover": synth("square", [[392, 392, 0.18], [330, 330, 0.18], [262, 262, 0.18], [196, 150, 0.6]], 0.14),
	}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


func synth(wave: String, segments: Array, volume: float, decay := 1.5) -> AudioStreamWAV:
	return to_stream(tone(wave, segments, volume, decay))


# Raw samples in -1..1. Higher `decay` makes each note fade faster (more plucky).
func tone(wave: String, segments: Array, volume: float, decay := 1.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var phase := 0.0
	var lp := 0.0  # low-pass state for "noise"
	for s in segments:
		var n := int(s[2] * SAMPLE_RATE)
		for k in n:
			var t := float(k) / n
			var freq: float = lerpf(s[0], s[1], t)
			phase = fmod(phase + freq / SAMPLE_RATE, 1.0)
			var v := 0.0
			match wave:
				"square": v = 1.0 if phase < 0.5 else -1.0
				"triangle": v = 4.0 * absf(phase - 0.5) - 1.0
				"sine": v = sin(phase * TAU)
				# Fundamental plus a quiet 4th harmonic gives a woody, mallet-like tone
				"marimba": v = (sin(phase * TAU) + 0.25 * sin(phase * TAU * 4.0)) / 1.25
				# Low-passed white noise: a soft, muffled tap rather than a hiss
				"noise":
					lp += 0.2 * (randf_range(-1.0, 1.0) - lp)
					v = lp * 2.5
			# Quick attack, smooth decay within each note
			var env := minf(1.0, k / (0.004 * SAMPLE_RATE)) * pow(1.0 - t, decay)
			out.append(v * env * volume)
	return out


# Mix several sample buffers together (they may differ in length).
func layer(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part: PackedFloat32Array in parts:
		if part.size() > out.size():
			out.resize(part.size())
		for i in part.size():
			out[i] += part[i]
	return out


func to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream


func play(sfx: String) -> void:
	var p := players[next_player]
	next_player = (next_player + 1) % VOICES
	p.stream = sounds[sfx]
	p.pitch_scale = randf_range(0.95, 1.05) if sfx in ["lock", "drop"] else 1.0
	p.play()


func _ready() -> void:
	font = ThemeDB.fallback_font
	randomize()
	build_sounds()
	get_viewport().size_changed.connect(recenter)
	recenter()
	load_save()
	for i in 14:
		var d := {}
		reset_decor(d, true)
		menu_decor.append(d)
	open_main_menu()


# The project scales the layout to the window ("canvas_items" stretch). When the window's
# shape differs from the layout's, "expand" adds the spare room on the right/bottom, so
# shift the layout to sit in the middle of it.
func recenter() -> void:
	position = ((get_viewport_rect().size - BASE_SIZE) / 2).floor()
	queue_redraw()


func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func new_game() -> void:
	grid.clear()
	for y in ROWS:
		var row := []
		row.resize(COLS)
		grid.append(row)
	next_queue.clear()
	fill_queue()
	hold_type = ""
	hold_used = false
	score = 0
	lines = 0
	level = start_level
	game_over = false
	paused = false
	new_best = false
	screen = "game"
	das_dir = 0
	particles.clear()
	spawn_piece(next_queue.pop_front())


func fill_queue() -> void:
	while next_queue.size() < 7:
		var bag := SHAPES.keys()
		bag.shuffle()
		next_queue.append_array(bag)


func spawn_piece(type: String) -> void:
	fill_queue()
	cur_type = type
	cur_rot = 0
	var size: int = SHAPES[type].n
	cur_pos = Vector2i((COLS - size) / 2, 0)
	fall_timer = 0.0
	lock_timer = 0.0
	lock_resets = 0
	if not fits(cur_type, cur_rot, cur_pos):
		end_game()
	queue_redraw()


func end_game() -> void:
	game_over = true
	play("gameover")
	if score > best:
		best = score
		new_best = true
		write_save()
	menu_sel = 0
	queue_redraw()


func get_cells(type: String, rot: int) -> Array:
	var shape: Dictionary = SHAPES[type]
	var n: int = shape.n
	var out := []
	for c in shape.cells:
		var p: Vector2i = c
		for i in rot % 4:
			p = Vector2i(n - 1 - p.y, p.x)
		out.append(p)
	return out


func fits(type: String, rot: int, pos: Vector2i) -> bool:
	for c in get_cells(type, rot):
		var p: Vector2i = pos + c
		if p.x < 0 or p.x >= COLS or p.y >= ROWS:
			return false
		if p.y >= 0 and grid[p.y][p.x] != null:
			return false
	return true


func on_successful_action() -> void:
	if lock_resets < MAX_LOCK_RESETS:
		lock_timer = 0.0
		lock_resets += 1
	queue_redraw()


func try_move(dx: int, dy: int) -> bool:
	var np := cur_pos + Vector2i(dx, dy)
	if fits(cur_type, cur_rot, np):
		cur_pos = np
		on_successful_action()
		if dx != 0:
			play("move_left" if dx < 0 else "move_right")
		return true
	return false


func try_rotate(dir: int) -> void:
	if cur_type == "O":
		return
	var nr := (cur_rot + dir + 4) % 4
	for k in KICKS:
		if fits(cur_type, nr, cur_pos + k):
			cur_rot = nr
			cur_pos += k
			on_successful_action()
			play("rotate")
			return


func hard_drop() -> void:
	while fits(cur_type, cur_rot, cur_pos + Vector2i.DOWN):
		cur_pos.y += 1
		score += 2
	play("drop")
	lock_piece()


func hold_piece() -> void:
	if hold_used:
		return
	play("hold")
	var prev := hold_type
	hold_type = cur_type
	if prev == "":
		spawn_piece(next_queue.pop_front())
	else:
		spawn_piece(prev)
	hold_used = true


func lock_piece() -> void:
	var color: Color = SHAPES[cur_type].color
	for c in get_cells(cur_type, cur_rot):
		var p: Vector2i = cur_pos + c
		if p.y < 0:
			end_game()
			return
		grid[p.y][p.x] = color
	clear_lines()
	hold_used = false
	spawn_piece(next_queue.pop_front())


func clear_lines() -> void:
	var cleared := []
	for y in ROWS:
		if not grid[y].has(null):
			cleared.append(y)
	if cleared.is_empty():
		return
	for y in cleared:
		spawn_row_particles(y)
		grid.remove_at(y)
		var row := []
		row.resize(COLS)
		grid.insert(0, row)
	lines += cleared.size()
	score += LINE_SCORES[cleared.size()] * level
	var old_level := level
	level = maxi(start_level, 1 + lines / 10)
	play("clear%d" % cleared.size())
	if level > old_level:
		play("levelup")


func gravity_interval() -> float:
	return maxf(0.05, 0.8 - (level - 1) * 0.07)


func spawn_row_particles(row: int) -> void:
	var shard := float(CELL) / SHARDS_PER_SIDE
	var row_center_x := BOARD_POS.x + COLS * CELL / 2.0
	for x in COLS:
		var color: Color = grid[row][x]
		var origin := cell_px(Vector2i(x, row))
		for sy in SHARDS_PER_SIDE:
			for sx in SHARDS_PER_SIDE:
				var pos := origin + Vector2(sx + 0.5, sy + 0.5) * shard
				# Burst outward from the middle of the row, with an upward kick
				var outward := (pos.x - row_center_x) / (COLS * CELL / 2.0)
				var vel := Vector2(outward * randf_range(150, 400) + randf_range(-120, 120), randf_range(-420, -80))
				var life := randf_range(0.6, 1.1)
				particles.append({
					"pos": pos,
					"vel": vel,
					"color": color.lightened(randf_range(0.0, 0.3)),
					"size": shard * randf_range(0.6, 1.0),
					"rot": randf() * TAU,
					"spin": randf_range(-12, 12),
					"life": life,
					"max_life": life,
				})


func update_particles(delta: float) -> void:
	if particles.is_empty():
		return
	for p in particles:
		var vel: Vector2 = p.vel
		vel.y += PARTICLE_GRAVITY * delta
		vel *= 0.99
		p.vel = vel
		p.pos += vel * delta
		p.rot += p.spin * delta
		p.life -= delta
	particles = particles.filter(func(p): return p.life > 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	update_particles(delta)
	if screen == "menu":
		update_decor(delta)
		return
	if game_over or paused:
		return

	# Horizontal movement with auto-repeat
	var right := Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D) \
		or pad_held(JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A) \
		or pad_held(JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0)
	var dir := int(right) - int(left)
	if dir != 0:
		if dir != das_dir:
			das_dir = dir
			das_timer = 0.0
			arr_timer = 0.0
			try_move(dir, 0)
		else:
			das_timer += delta
			if das_timer >= DAS:
				arr_timer += delta
				while arr_timer >= ARR:
					arr_timer -= ARR
					try_move(dir, 0)
	else:
		das_dir = 0

	# Gravity (faster while soft dropping)
	var soft := Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S) \
		or pad_held(JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	var interval := gravity_interval()
	if soft:
		interval = minf(interval, 0.04)
	fall_timer += delta
	while fall_timer >= interval:
		fall_timer -= interval
		if fits(cur_type, cur_rot, cur_pos + Vector2i.DOWN):
			cur_pos.y += 1
			if soft:
				score += 1
			queue_redraw()
		else:
			fall_timer = 0.0
			break

	# Lock delay once grounded
	if fits(cur_type, cur_rot, cur_pos + Vector2i.DOWN):
		lock_timer = 0.0
	else:
		lock_timer += delta
		if lock_timer >= LOCK_DELAY:
			play("lock")
			lock_piece()


# Gamepad buttons act as the keyboard key with the same job.
const PAD_KEYS := {
	JOY_BUTTON_A: KEY_X,                    # rotate clockwise
	JOY_BUTTON_RIGHT_SHOULDER: KEY_X,
	JOY_BUTTON_B: KEY_Z,                    # rotate counter-clockwise
	JOY_BUTTON_LEFT_SHOULDER: KEY_Z,
	JOY_BUTTON_DPAD_UP: KEY_SPACE,          # hard drop
	JOY_BUTTON_Y: KEY_SPACE,
	JOY_BUTTON_X: KEY_C,                    # hold
	JOY_BUTTON_START: KEY_P,                # pause
	JOY_BUTTON_BACK: KEY_R,                 # restart
}
const STICK_DEADZONE := 0.5


# True if any connected gamepad holds this D-pad button or pushes the stick that way.
func pad_held(button: JoyButton, axis: JoyAxis, sign: float) -> bool:
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, button) or Input.get_joy_axis(id, axis) * sign > STICK_DEADZONE:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_F11 or (event.physical_keycode == KEY_ENTER and event.alt_pressed)):
		toggle_fullscreen()
		return
	if not current_menu().is_empty():
		menu_input(event)
		return

	var key: Key = KEY_NONE
	if event is InputEventKey and event.pressed and not event.echo:
		key = event.physical_keycode
	elif event is InputEventJoypadButton and event.pressed:
		key = PAD_KEYS.get(event.button_index, KEY_NONE)
	if key == KEY_NONE:
		return
	if key == KEY_P or key == KEY_ESCAPE:
		paused = true
		menu_sel = 0
		play("pause")
		queue_redraw()
		return
	match key:
		KEY_UP, KEY_W, KEY_X:
			try_rotate(1)
		KEY_Z, KEY_CTRL:
			try_rotate(-1)
		KEY_SPACE:
			hard_drop()
		KEY_C, KEY_SHIFT:
			hold_piece()
		KEY_R:
			new_game()


# ---------------------------------------------------------------- menus
# The title, pause and game-over screens are each a list of [id, label] buttons that work
# with keyboard, gamepad and mouse.

func current_menu() -> Array:
	if screen == "menu":
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		return [
			["play", "Play"],
			["level", "Start level:   <  %d  >" % start_level],
			["fullscreen", "Fullscreen:  %s" % ("On" if fs else "Off")],
			["quit", "Quit"],
		]
	if game_over:
		return [["play", "Play again"], ["menu", "Main menu"]]
	if paused:
		return [["resume", "Resume"], ["play", "Restart"], ["menu", "Main menu"]]
	return []


func menu_rects(count: int) -> Array:
	var size: Vector2 = Vector2(270, 46) if screen == "menu" else Vector2(200, 40)
	var gap := 14.0
	var center_x: float = BASE_SIZE.x / 2.0 if screen == "menu" else BOARD_POS.x + COLS * CELL / 2.0
	var top: float = 290.0 if screen == "menu" else BOARD_POS.y + ROWS * CELL / 2.0 + 10.0
	var out := []
	for i in count:
		out.append(Rect2(Vector2(center_x - size.x / 2.0, top + i * (size.y + gap)), size))
	return out


func open_main_menu() -> void:
	screen = "menu"
	paused = false
	game_over = false
	particles.clear()
	menu_sel = 0
	queue_redraw()


func menu_input(event: InputEvent) -> void:
	var items := current_menu()
	var action := ""
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_UP, KEY_W: action = "up"
			KEY_DOWN, KEY_S: action = "down"
			KEY_LEFT, KEY_A: action = "left"
			KEY_RIGHT, KEY_D: action = "right"
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: action = "" if event.echo else "ok"
			KEY_ESCAPE, KEY_P: action = "" if event.echo else "back"
			KEY_R:
				if game_over:
					activate("play")
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: action = "up"
			JOY_BUTTON_DPAD_DOWN: action = "down"
			JOY_BUTTON_DPAD_LEFT: action = "left"
			JOY_BUTTON_DPAD_RIGHT: action = "right"
			JOY_BUTTON_A: action = "ok"
			JOY_BUTTON_B: action = "back"
			JOY_BUTTON_START: action = "back" if paused else "ok"
	elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		# Treat the stick like a D-pad: act once each time it's pushed past the deadzone
		var was: float = stick_prev.get(event.axis, 0.0)
		stick_prev[event.axis] = event.axis_value
		if absf(was) <= STICK_DEADZONE and absf(event.axis_value) > STICK_DEADZONE:
			if event.axis == JOY_AXIS_LEFT_Y:
				action = "down" if event.axis_value > 0 else "up"
			else:
				action = "right" if event.axis_value > 0 else "left"
	elif event is InputEventMouseMotion:
		var i := menu_item_at(get_local_mouse_position())
		if i >= 0 and i != menu_sel:
			menu_sel = i
			play("move_right")
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := menu_item_at(get_local_mouse_position())
		if i >= 0:
			menu_sel = i
			action = "ok"

	match action:
		"up", "down":
			menu_sel = (menu_sel + (1 if action == "down" else -1) + items.size()) % items.size()
			play("move_left" if action == "up" else "move_right")
		"left", "right":
			adjust(items[menu_sel][0], 1 if action == "right" else -1)
		"ok":
			activate(items[menu_sel][0])
		"back":
			if paused and not game_over:
				activate("resume")
			elif game_over:
				activate("menu")
	queue_redraw()


func menu_item_at(p: Vector2) -> int:
	var rects := menu_rects(current_menu().size())
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	return -1


# Left/right on a setting changes it.
func adjust(id: String, dir: int) -> void:
	match id:
		"level":
			start_level = wrapi(start_level + dir, 1, MAX_START_LEVEL + 1)
			play("rotate")
			write_save()
		"fullscreen":
			toggle_fullscreen()
			play("rotate")


func activate(id: String) -> void:
	match id:
		"play":
			play("hold")
			new_game()
		"level":
			adjust(id, 1)
		"fullscreen":
			adjust(id, 1)
		"quit":
			get_tree().quit()
		"resume":
			paused = false
			play("pause")
		"menu":
			play("pause")
			open_main_menu()
	queue_redraw()


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = cfg.get_value("scores", "best", 0)
		start_level = clampi(cfg.get_value("settings", "start_level", 1), 1, MAX_START_LEVEL)


func write_save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "best", best)
	cfg.set_value("settings", "start_level", start_level)
	cfg.save(SAVE_PATH)


# Background pieces on the title screen; `anywhere` scatters them over the whole window
# (at startup) instead of starting them just above the top edge.
func reset_decor(d: Dictionary, anywhere: bool) -> void:
	var view := Rect2(-position, get_viewport_rect().size)
	d.type = SHAPES.keys().pick_random()
	d.size = randf_range(14.0, 30.0)
	d.speed = randf_range(20.0, 60.0)
	d.spin = randf_range(-0.6, 0.6)
	d.angle = randf() * TAU
	var y: float = randf_range(view.position.y, view.end.y) if anywhere else view.position.y - 80.0
	d.pos = Vector2(randf_range(view.position.x, view.end.x), y)


func update_decor(delta: float) -> void:
	menu_time += delta
	var bottom := -position.y + get_viewport_rect().size.y + 80.0
	for d in menu_decor:
		d.pos.y += d.speed * delta
		d.angle += d.spin * delta
		if d.pos.y > bottom:
			reset_decor(d, false)
	queue_redraw()


# ---------------------------------------------------------------- drawing
# Light comes from the top-left: top/left faces are lit, bottom/right are in shade,
# and shadows fall down and to the right.

const SHADOW_OFFSET := Vector2(4, 5)
const FRAME := 7.0

func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), color)


func gradient_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


# Four slanted faces around an inner rectangle, like a picture frame or a block's bevel.
func bevel(outer: Rect2, t: float, top: Color, left: Color, right: Color, bottom: Color) -> void:
	var inner := outer.grow(-t)
	var o_tl := outer.position
	var o_tr := Vector2(outer.end.x, outer.position.y)
	var o_br := outer.end
	var o_bl := Vector2(outer.position.x, outer.end.y)
	var i_tl := inner.position
	var i_tr := Vector2(inner.end.x, inner.position.y)
	var i_br := inner.end
	var i_bl := Vector2(inner.position.x, inner.end.y)
	quad(o_tl, o_tr, i_tr, i_tl, top)
	quad(o_tl, i_tl, i_bl, o_bl, left)
	quad(o_tr, o_br, i_br, i_tr, right)
	quad(o_bl, i_bl, i_br, o_br, bottom)


func draw_cell(px: Vector2, size: float, color: Color, alpha := 1.0) -> void:
	var r := Rect2(px, Vector2(size, size)).grow(-1)
	var b := maxf(2.0, size * 0.18)
	bevel(r, b,
		Color(color.lightened(0.5), alpha),
		Color(color.lightened(0.2), alpha),
		Color(color.darkened(0.3), alpha),
		Color(color.darkened(0.5), alpha))
	var face := r.grow(-b)
	gradient_rect(face, Color(color.lightened(0.12), alpha), Color(color.darkened(0.12), alpha))
	# Glossy highlight
	draw_rect(Rect2(face.position + Vector2(1, 1), Vector2(face.size.x * 0.45, maxf(1.5, size * 0.07))), Color(1, 1, 1, 0.45 * alpha))


func draw_cell_shadow(px: Vector2, size: float) -> void:
	draw_rect(Rect2(px + SHADOW_OFFSET * size / CELL, Vector2(size, size)).grow(-1), Color(0, 0, 0, 0.3))


# A sunken well (board, side boxes) set into a raised frame.
func draw_well(r: Rect2) -> void:
	var outer := r.grow(FRAME)
	draw_rect(Rect2(outer.position + Vector2(6, 8), outer.size), Color(0, 0, 0, 0.45))
	bevel(outer, FRAME, Color("ff8fd2"), Color("e85cb3"), Color("9a2f86"), Color("6a1f63"))
	gradient_rect(r, Color("231245"), Color("33195e"))
	# Inner shadow cast by the frame onto the well
	gradient_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0))
	draw_polygon(
		PackedVector2Array([r.position, r.position + Vector2(12, 0), Vector2(r.position.x + 12, r.end.y), Vector2(r.position.x, r.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0.4), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.4)]))


func cell_px(p: Vector2i) -> Vector2:
	return BOARD_POS + Vector2(p.x * CELL, p.y * CELL)


func draw_mini_piece(type: String, center: Vector2, size: float, alpha := 1.0) -> void:
	var cells := get_cells(type, 0)
	var min_p := Vector2(99, 99)
	var max_p := Vector2(-99, -99)
	for c in cells:
		min_p = min_p.min(Vector2(c))
		max_p = max_p.max(Vector2(c))
	var dims := (max_p - min_p + Vector2.ONE) * size
	var origin := center - dims / 2.0
	for c in cells:
		draw_cell_shadow(origin + (Vector2(c) - min_p) * size, size)
	for c in cells:
		draw_cell(origin + (Vector2(c) - min_p) * size, size, SHAPES[type].color, alpha)


func draw_text(text: String, pos: Vector2, size: int, color := Color.WHITE) -> void:
	draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func draw_centered(text: String, y: float, size: int, color := Color.WHITE) -> void:
	var w := COLS * CELL
	draw_string(font, Vector2(BOARD_POS.x + 3, y + 3), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(BOARD_POS.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)


func _draw() -> void:
	# Fill the whole window, including any room around the centred layout
	var view := get_viewport_rect()
	gradient_rect(Rect2(view.position - position, view.size), Color("4a2a8c"), Color("1c0f42"))
	if screen == "menu":
		draw_main_menu()
		return

	# Board well and grid
	var board := Rect2(BOARD_POS, Vector2(COLS * CELL, ROWS * CELL))
	draw_well(board)
	for x in COLS + 1:
		draw_line(BOARD_POS + Vector2(x * CELL, 0), BOARD_POS + Vector2(x * CELL, ROWS * CELL), Color(1.0, 0.8, 1.0, 0.07))
	for y in ROWS + 1:
		draw_line(BOARD_POS + Vector2(0, y * CELL), BOARD_POS + Vector2(COLS * CELL, y * CELL), Color(1.0, 0.8, 1.0, 0.07))

	# Collect every solid block first so all shadows go underneath all blocks
	var blocks := []  # [position, color]
	for y in ROWS:
		for x in COLS:
			if grid[y][x] != null:
				blocks.append([cell_px(Vector2i(x, y)), grid[y][x]])
	if not game_over:
		var col: Color = SHAPES[cur_type].color
		for c in get_cells(cur_type, cur_rot):
			var p: Vector2i = cur_pos + c
			if p.y >= 0:
				blocks.append([cell_px(p), col])

		# Ghost piece: a faint, see-through block where the piece will land
		var ghost := cur_pos
		while fits(cur_type, cur_rot, ghost + Vector2i.DOWN):
			ghost.y += 1
		for c in get_cells(cur_type, cur_rot):
			var p: Vector2i = ghost + c
			if p.y >= 0:
				draw_cell(cell_px(p), CELL, col, 0.18)

	for b in blocks:
		draw_cell_shadow(b[0], CELL)
	for b in blocks:
		draw_cell(b[0], CELL, b[1])

	# Side panel
	var y := 40.0
	draw_text("NEXT", Vector2(PANEL_X, y), 20, Color("ffd93b"))
	draw_well(Rect2(PANEL_X, y + 12, 150, 196))
	for i in 3:
		draw_mini_piece(next_queue[i], Vector2(PANEL_X + 75, y + 45 + i * 64), 20.0 if i == 0 else 16.0)

	y = 290.0
	draw_text("HOLD", Vector2(PANEL_X, y), 20, Color("3ee0ff"))
	draw_well(Rect2(PANEL_X, y + 12, 150, 68))
	if hold_type != "":
		draw_mini_piece(hold_type, Vector2(PANEL_X + 75, y + 46), 18.0, 0.35 if hold_used else 1.0)

	draw_well(Rect2(PANEL_X, 390, 150, 162))
	y = 412.0
	for pair in [["SCORE", str(score), Color("ff4f8b")], ["LEVEL", str(level), Color("5cec6b")], ["LINES", str(lines), Color("ff8a3d")]]:
		draw_text(pair[0], Vector2(PANEL_X + 12, y), 14, pair[2])
		draw_text(pair[1], Vector2(PANEL_X + 12, y + 26), 24)
		y += 52.0

	var help := ["Arrows / WASD: move / soft drop", "Up / W / X: rotate   Z: ccw", "Space: hard drop", "C: hold   P / Esc: pause menu", "F11: fullscreen  (gamepad ok)"]
	for i in help.size():
		draw_text(help[i], Vector2(PANEL_X, 570 + i * 14), 12, Color("c4a8ff"))

	# Line clear particles: little beveled shards with a shadow
	for p in particles:
		var t: float = p.life / p.max_life
		var s: float = p.size * (0.4 + 0.6 * t)
		var c: Color = p.color
		var half := Vector2(-s, -s) / 2.0
		draw_set_transform(p.pos + Vector2(3, 4), p.rot)
		draw_rect(Rect2(half, Vector2(s, s)), Color(0, 0, 0, 0.3 * t))
		draw_set_transform(p.pos, p.rot)
		draw_rect(Rect2(half, Vector2(s, s)), Color(c.darkened(0.35), t))
		draw_rect(Rect2(half, Vector2(s, s) * 0.75), Color(c.lightened(0.25), t))
	draw_set_transform(Vector2.ZERO)

	# Overlays
	if game_over or paused:
		draw_rect(board, Color(0, 0, 0, 0.65))
		var mid := BOARD_POS.y + ROWS * CELL / 2.0
		if game_over:
			draw_centered("GAME OVER", mid - 90, 32, Color("ff4f8b"))
			draw_centered("Score  %d" % score, mid - 52, 18)
			if new_best:
				draw_centered("NEW BEST!", mid - 22, 18, Color("ffd93b"))
			else:
				draw_centered("Best  %d" % best, mid - 22, 14, Color("c4a8ff"))
		else:
			draw_centered("PAUSED", mid - 40, 32)
		draw_menu_buttons()


func draw_menu_buttons() -> void:
	var items := current_menu()
	var rects := menu_rects(items.size())
	var size: int = 20 if screen == "menu" else 17
	for i in items.size():
		var r: Rect2 = rects[i]
		var selected := i == menu_sel
		if selected:
			draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.4))
			bevel(r, 4.0, Color("ff8fd2"), Color("e85cb3"), Color("9a2f86"), Color("6a1f63"))
			gradient_rect(r.grow(-4.0), Color("7a3fc4"), Color("4f2296"))
		else:
			draw_rect(r, Color("1c0f42", 0.85))
			draw_rect(r, Color(1.0, 0.8, 1.0, 0.25), false, 1.5)
		var y := r.position.y + r.size.y / 2.0 + size * 0.35
		draw_string(font, Vector2(r.position.x + 2, y + 2), items[i][1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(r.position.x, y), items[i][1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, Color.WHITE if selected else Color("c4a8ff"))


func draw_main_menu() -> void:
	# Pieces drifting down in the background
	for d in menu_decor:
		draw_set_transform(d.pos, d.angle)
		draw_mini_piece(d.type, Vector2.ZERO, d.size, 0.25)
	draw_set_transform(Vector2.ZERO)

	# Title: each letter in a piece colour, bobbing in a gentle wave
	var colors := SHAPES.values().map(func(s): return s.color)
	var title_size := 64
	var x := (BASE_SIZE.x - font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x) / 2.0
	for i in TITLE.length():
		var ch := TITLE[i]
		var y := 170.0 + sin(menu_time * 3.0 - i * 0.6) * 5.0
		draw_string_outline(font, Vector2(x + 3, y + 5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 12, Color(0, 0, 0, 0.45))
		draw_string_outline(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 10, Color("1c0f42"))
		draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, colors[i % colors.size()])
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x

	if best > 0:
		draw_string(font, Vector2(0, 236), "BEST  %d" % best, HORIZONTAL_ALIGNMENT_CENTER, BASE_SIZE.x, 18, Color("ffd93b"))

	draw_menu_buttons()

	draw_string(font, Vector2(0, 610), "Arrows / WASD + Enter    ·    Gamepad    ·    Mouse", HORIZONTAL_ALIGNMENT_CENTER, BASE_SIZE.x, 13, Color("c4a8ff"))
