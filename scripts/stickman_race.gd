extends Node2D

enum RaceState { COUNTDOWN, RACING, FINISHED }

const GROUND_Y: float = 430.0
const FINISH_X: float = 2350.0
const TRACK_END: float = 2450.0

const DIRT := Color(0.55, 0.38, 0.22)
const DIRT_DARK := Color(0.4, 0.27, 0.15)
const GRASS := Color(0.35, 0.75, 0.3)
const GRASS_DARK := Color(0.25, 0.55, 0.22)
const SKY := Color(0.45, 0.8, 0.95)
const SPIKE_COL := Color(0.7, 0.72, 0.78)
const SPIKE_DARK := Color(0.3, 0.3, 0.35)

var state: RaceState = RaceState.COUNTDOWN
var runners: Array[StickmanRunner] = []
var player: StickmanRunner = null
var checkpoints: Array[float] = [40.0, 570.0, 990.0, 1470.0, 1980.0]

var camera: Camera2D
var ui: CanvasLayer
var countdown_label: Label
var rank_label: Label
var progress_dots: Array[ColorRect] = []
var results_panel: Control
var results_list: VBoxContainer
var results_title: Label

var jump_player: AudioStreamPlayer
var point_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer

var end_wait: float = -1.0
var race_elapsed: float = 0.0
const RACE_TIMEOUT: float = 150.0

const RACERS := [
	{"name": "SEN", "color": Color(1.0, 0.85, 0.2), "player": true, "speed": 140.0, "anti": 80.0},
	{"name": "BOT Maviş", "color": Color(0.3, 0.6, 1.0), "player": false, "speed": 144.0, "anti": 82.0},
	{"name": "BOT Kırmızı", "color": Color(1.0, 0.3, 0.3), "player": false, "speed": 147.0, "anti": 78.0},
	{"name": "BOT Yeşil", "color": Color(0.3, 0.85, 0.4), "player": false, "speed": 141.0, "anti": 86.0},
]

func _ready() -> void:
	camera = $Camera2D
	ui = $RaceUI
	_build_sky()
	_build_track()
	_build_runners()
	_build_audio()
	_build_ui()
	_start_countdown()

# --- PİST ---
func _add_platform(x0: float, x1: float, top_y: float = GROUND_Y) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2((x0 + x1) * 0.5, top_y + 300.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(x1 - x0, 600.0)
	shape.shape = rect
	body.add_child(shape)
	var dirt := Polygon2D.new()
	var w = (x1 - x0) * 0.5
	dirt.polygon = PackedVector2Array([Vector2(-w, -300), Vector2(w, -300), Vector2(w, 300), Vector2(-w, 300)])
	dirt.color = DIRT
	body.add_child(dirt)
	var grass := Polygon2D.new()
	grass.polygon = PackedVector2Array([Vector2(-w, -300), Vector2(w, -300), Vector2(w, -288), Vector2(-w, -288)])
	grass.color = GRASS
	body.add_child(grass)
	add_child(body)

func _add_spike(x_center: float, top_y: float = GROUND_Y) -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(x_center, top_y - 12.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 24)
	shape.shape = rect
	area.add_child(shape)
	var tris := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(3):
		var bx = -13.0 + i * 8.0
		pts.append_array([Vector2(bx, 12), Vector2(bx + 4.0, -12), Vector2(bx + 8.0, 12)])
	tris.polygon = pts
	tris.color = SPIKE_COL
	area.add_child(tris)
	area.body_entered.connect(_on_spike_body.bind(area))
	add_child(area)

func _add_stairs(x_start: float, base_top: float, steps: int) -> void:
	var w := 22.0
	var h := 16.0
	for i in range(steps):
		_add_platform(x_start + i * w, x_start + (i + 1) * w, base_top - (i + 1) * h)

func _add_finish() -> void:
	var pole := Polygon2D.new()
	pole.polygon = PackedVector2Array([Vector2(-3, -190), Vector2(3, -190), Vector2(3, 0), Vector2(-3, 0)])
	pole.color = Color(0.45, 0.3, 0.18)
	pole.position = Vector2(FINISH_X, GROUND_Y)
	add_child(pole)
	var pts := PackedVector2Array()
	for r in range(2):
		for c in range(4):
			var x0 = 3.0 + c * 9.0
			var y0 = -190.0 + r * 9.0
			if (r + c) % 2 == 0:
				pts.append_array([Vector2(x0, y0), Vector2(x0 + 9, y0), Vector2(x0 + 9, y0 + 9)])
				pts.append_array([Vector2(x0, y0), Vector2(x0 + 9, y0 + 9), Vector2(x0, y0 + 9)])
	var flag_node := Polygon2D.new()
	flag_node.polygon = pts
	flag_node.color = Color.WHITE
	flag_node.position = Vector2(FINISH_X, GROUND_Y)
	add_child(flag_node)
	var flag_dark := Polygon2D.new()
	var pts2 := PackedVector2Array()
	for r in range(2):
		for c in range(4):
			if (r + c) % 2 == 1:
				var x1 = 3.0 + c * 9.0
				var y1 = -190.0 + r * 9.0
				pts2.append_array([Vector2(x1, y1), Vector2(x1 + 9, y1), Vector2(x1 + 9, y1 + 9)])
				pts2.append_array([Vector2(x1, y1), Vector2(x1 + 9, y1 + 9), Vector2(x1, y1 + 9)])
	flag_dark.polygon = pts2
	flag_dark.color = Color(0.15, 0.15, 0.2)
	flag_dark.position = Vector2(FINISH_X, GROUND_Y)
	add_child(flag_dark)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(FINISH_X, GROUND_Y - 100.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 220)
	shape.shape = rect
	area.add_child(shape)
	area.body_entered.connect(_on_finish_body)
	add_child(area)

func _build_sky() -> void:
	var sky := ColorRect.new()
	sky.color = SKY
	sky.offset_right = TRACK_END + 200.0
	sky.offset_bottom = 512.0
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	move_child(sky, 0)

func _build_track() -> void:
	_add_platform(0, 500)
	_add_platform(570, 900)
	_add_spike(700)
	_add_stairs(820, GROUND_Y, 2)
	_add_platform(990, 1400)
	_add_spike(1100)
	_add_spike(1250)
	_add_platform(1470, 1900)
	_add_spike(1800)
	_add_platform(1980, TRACK_END)
	_add_finish()

func _build_runners() -> void:
	var spawn_x := 40.0
	for cfg in RACERS:
		var r := StickmanRunner.new()
		r.setup(String(cfg["name"]), cfg["color"], bool(cfg["player"]), float(cfg["speed"]), float(cfg["anti"]))
		r.position = Vector2(spawn_x, GROUND_Y - 40.0)
		r.respawn_pos = r.position
		r.jumped.connect(_on_runner_jumped)
		add_child(r)
		runners.append(r)
		if r.is_player:
			player = r
		spawn_x -= 24.0

func _build_audio() -> void:
	jump_player = _make_player("res://assets/audio/wing.ogg")
	point_player = _make_player("res://assets/audio/point.ogg")
	hit_player = _make_player("res://assets/audio/hit.ogg")

func _make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path) as AudioStream
	add_child(p)
	return p

# --- UI ---
func _build_ui() -> void:
	countdown_label = Label.new()
	countdown_label.add_theme_font_size_override("font_size", 44)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	countdown_label.add_theme_constant_override("outline_size", 8)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -60.0
	countdown_label.offset_top = -140.0
	countdown_label.offset_right = 60.0
	countdown_label.offset_bottom = -80.0
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(countdown_label)

	var bar := PanelContainer.new()
	var bstyle := StyleBoxFlat.new()
	bstyle.set_corner_radius_all(6)
	bstyle.bg_color = Color(0, 0, 0, 0.45)
	bar.add_theme_stylebox_override("panel", bstyle)
	bar.offset_left = 24.0
	bar.offset_top = 8.0
	bar.offset_right = 264.0
	bar.offset_bottom = 30.0
	ui.add_child(bar)
	for i in range(runners.size()):
		var dot := ColorRect.new()
		dot.color = (runners[i] as StickmanRunner).body_color
		dot.custom_minimum_size = Vector2(8, 8)
		dot.position = Vector2(30, 13)
		ui.add_child(dot)
		progress_dots.append(dot)

	rank_label = Label.new()
	rank_label.add_theme_font_size_override("font_size", 13)
	rank_label.add_theme_color_override("font_color", Color.WHITE)
	rank_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rank_label.add_theme_constant_override("outline_size", 4)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.offset_left = 24.0
	rank_label.offset_top = 32.0
	rank_label.offset_right = 264.0
	rank_label.offset_bottom = 52.0
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(rank_label)

	_build_results()

func _build_results() -> void:
	results_panel = Control.new()
	results_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_panel.visible = false
	ui.add_child(results_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_panel.add_child(dim)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.bg_color = Color(0.16, 0.14, 0.22, 0.97)
	style.border_color = Color(1.0, 0.85, 0.2, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	panel.offset_left = 34.0
	panel.offset_top = 120.0
	panel.offset_right = 254.0
	panel.offset_bottom = 400.0
	results_panel.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	results_title = Label.new()
	results_title.add_theme_font_size_override("font_size", 15)
	results_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(results_title)
	results_list = VBoxContainer.new()
	results_list.add_theme_constant_override("separation", 3)
	vbox.add_child(results_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	var again := Button.new()
	again.text = "🔄 TEKRAR"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func(): get_tree().reload_current_scene())
	row.add_child(again)
	var menu_btn := Button.new()
	menu_btn.text = "🏠 MENÜ"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/multiplayer_menu.tscn"))
	row.add_child(menu_btn)

func _show_count(txt: String) -> void:
	if countdown_label:
		countdown_label.text = txt
	if point_player:
		point_player.play()

func _start_countdown() -> void:
	state = RaceState.COUNTDOWN
	countdown_label.visible = true
	var tween = create_tween()
	for txt in ["3", "2", "1"]:
		tween.tween_callback(_show_count.bind(txt))
		tween.tween_interval(0.8)
	# son adım: UÇ + başlat
	tween.tween_callback(func():
		countdown_label.text = "UÇ!"
		if jump_player:
			jump_player.play()
		_begin_race()
	)
	tween.tween_interval(0.5)
	tween.tween_callback(func(): countdown_label.visible = false)

func _begin_race() -> void:
	if state != RaceState.COUNTDOWN:
		return
	state = RaceState.RACING
	race_elapsed = 0.0
	end_wait = -1.0
	for r in runners:
		(r as StickmanRunner).start_race()

# --- INPUT ---
func _unhandled_input(event: InputEvent) -> void:
	if state != RaceState.RACING or player == null or player.finished:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("flap"):
		player.press_jump()
	elif event.is_action_released("flap"):
		player.release_jump()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			player.press_jump()
		else:
			player.release_jump()
	elif event is InputEventScreenTouch:
		if event.pressed:
			player.press_jump()
		else:
			player.release_jump()

# --- OLAYLAR ---
func _on_runner_jumped(_runner: StickmanRunner) -> void:
	if jump_player and _runner.is_player:
		jump_player.play()

func _on_spike_body(body: Node2D, _area: Area2D) -> void:
	if body is StickmanRunner and not (body as StickmanRunner).finished:
		if hit_player:
			hit_player.play()
		(body as StickmanRunner).do_respawn()
		_flash_runner(body as StickmanRunner)

func _flash_runner(r: StickmanRunner) -> void:
	r.modulate = Color(1, 0.4, 0.4)
	var tween = create_tween()
	tween.tween_interval(0.25)
	tween.tween_callback(func(): r.modulate = Color.WHITE)

func _on_finish_body(body: Node2D) -> void:
	if body is StickmanRunner:
		_finish_runner(body as StickmanRunner)

func _finish_runner(r: StickmanRunner) -> void:
	if r.finished or state != RaceState.RACING:
		return
	r.finished = true
	r.finish_time = r.race_time
	if point_player:
		point_player.play()
	if r == player:
		end_wait = 5.0

# --- DÖNGÜ ---
func _process(delta: float) -> void:
	if state != RaceState.RACING:
		return
	# Lastik bant: botlar oyuncuya göre hafif ayarlanır
	if player:
		for r in runners:
			var rr = r as StickmanRunner
			if rr.is_player or rr.finished:
				continue
			var diff = player.position.x - rr.position.x
			rr.speed_factor = clampf(1.0 + diff / 1500.0, 0.92, 1.08)
		# Checkpoint takibi
		for r in runners:
			var rr2 = r as StickmanRunner
			if rr2.finished:
				continue
			for cp in checkpoints:
				if rr2.position.x > cp + 10.0 and cp > rr2.respawn_pos.x:
					rr2.respawn_pos = Vector2(cp, GROUND_Y - 40.0)
		# Kamera
		if camera:
			camera.position.x = clampf(player.position.x + 40.0, 144.0, TRACK_END - 144.0)
		_update_race_ui()
	# Bitiş kontrolü
	var all_done = true
	for r in runners:
		if not (r as StickmanRunner).finished:
			all_done = false
			break
	if all_done:
		_end_race()
		return
	# Botlar bitti ama oyuncu takıldıysa 10 sn daha bekle
	var bots_done = true
	for r in runners:
		var rr = r as StickmanRunner
		if not rr.is_player and not rr.finished:
			bots_done = false
			break
	if bots_done and not player.finished and end_wait < 0.0:
		end_wait = 10.0
	if end_wait > 0.0:
		end_wait -= delta
		if end_wait <= 0.0:
			_end_race()
			return
	# Global güvenlik süresi (takılmaya karşı)
	race_elapsed += delta
	if race_elapsed >= RACE_TIMEOUT:
		_end_race()

func _ranked_runners() -> Array:
	var arr: Array = runners.duplicate()
	arr.sort_custom(func(a, b):
		var ra = a as StickmanRunner
		var rb = b as StickmanRunner
		if ra.finished and rb.finished:
			return ra.finish_time < rb.finish_time
		if ra.finished:
			return true
		if rb.finished:
			return false
		return ra.position.x > rb.position.x
	)
	return arr

func _update_race_ui() -> void:
	for i in range(runners.size()):
		var rr = runners[i] as StickmanRunner
		var prog = clampf(rr.position.x / FINISH_X, 0.0, 1.0)
		if i < progress_dots.size():
			progress_dots[i].position.x = 30.0 + prog * 210.0
	var order = _ranked_runners()
	var my_rank = order.find(player) + 1
	if rank_label:
		rank_label.text = "%d. SIRA" % my_rank
		if my_rank == 1:
			rank_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			rank_label.add_theme_color_override("font_color", Color.WHITE)

func _end_race() -> void:
	if state != RaceState.RACING:
		return
	state = RaceState.FINISHED
	for r in runners:
		(r as StickmanRunner).racing = false
	var order = _ranked_runners()
	var won = order[0] == player
	if results_title:
		if won:
			results_title.text = "🏆 KAZANDIN!"
			results_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			results_title.text = "🏁 YARIŞ BİTTİ"
			results_title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
		if point_player:
			point_player.play()
	if results_list:
		for child in results_list.get_children():
			child.queue_free()
		var medals := ["🥇", "🥈", "🥉", "4."]
		var idx = 0
		for r in order:
			var rr = r as StickmanRunner
			var line := Label.new()
			var detail = ""
			if rr.finished:
				detail = "%.1f sn" % rr.finish_time
			else:
				detail = "%d%%" % int(clampf(rr.position.x / FINISH_X, 0.0, 1.0) * 100.0)
			line.text = "%s %s — %s" % [medals[mini(idx, 3)], rr.racer_name, detail]
			line.add_theme_font_size_override("font_size", 12)
			if rr == player:
				line.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			results_list.add_child(line)
			idx += 1
	if results_panel:
		results_panel.visible = true
