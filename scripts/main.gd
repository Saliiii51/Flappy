extends Node2D

enum GameState { READY, PLAYING, GAME_OVER }
enum Weather { NONE, TAILWIND, HEADWIND, FOG }

const SAVE_PATH: String = "user://flappy_save.cfg"

@onready var bird: Bird = $Bird
@onready var ground: Ground = $Ground
@onready var pipe_spawner: PipeSpawner = $PipeSpawner
@onready var pipes_container: Node2D = $PipesContainer
@onready var ui: GameUI = $UI
@onready var audio_manager: Node = $AudioManager
@onready var camera: Camera2D = $Camera2D
@onready var background: Sprite2D = $Background
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var lightning_flash: ColorRect = $LightningFlash
@onready var achievements: Node = $AchievementsManager

var day_texture: Texture2D = preload("res://assets/sprites/background-day.png")
var night_texture: Texture2D = preload("res://assets/sprites/background-night.png")

var boss_scene: PackedScene = preload("res://scenes/boss.tscn")
var boss_projectile_scene: PackedScene = preload("res://scenes/boss_projectile.tscn")
var boss_bomb_scene: PackedScene = preload("res://scenes/boss_bomb.tscn")

var state: GameState = GameState.READY
var score: int = 0
var high_score: int = 0
var saved_skin: String = "yellow"
var can_restart: bool = false
var is_night: bool = false
var lightning_timer: float = 14.0

var next_boss_score: int = 100
var boss_active: bool = false
var current_boss: Node2D = null
var boss_level: int = 0

var weather: Weather = Weather.NONE
var weather_time_left: float = 0.0
var weather_elapsed: float = 0.0
var next_weather_score: int = 8
var wind_pipe_bonus: float = 0.0
var bird_base_x: float = 70.0
var wind_particles: CPUParticles2D
var fog_rect: ColorRect

const WEATHER_DURATION: float = 6.0

func _ready() -> void:
	load_save_data()
	_build_weather_nodes()
	
	if bird:
		if not bird.died.is_connected(_on_bird_died):
			bird.died.connect(_on_bird_died)
		if not bird.shield_absorbed.is_connected(_on_shield_absorbed):
			bird.shield_absorbed.connect(_on_shield_absorbed)
		if not bird.double_score_toggled.is_connected(_on_double_score_toggled):
			bird.double_score_toggled.connect(_on_double_score_toggled)
		bird.set_skin(saved_skin)
	
	if ground and not ground.bird_hit.is_connected(_on_ground_hit):
		ground.bird_hit.connect(_on_ground_hit)
	
	if pipe_spawner:
		if not pipe_spawner.pipe_spawned.is_connected(_on_pipe_spawned):
			pipe_spawner.pipe_spawned.connect(_on_pipe_spawned)
		if not pipe_spawner.powerup_spawned.is_connected(_on_powerup_spawned):
			pipe_spawner.powerup_spawned.connect(_on_powerup_spawned)
	
	if ui:
		if not ui.skin_changed.is_connected(_on_skin_changed):
			ui.skin_changed.connect(_on_skin_changed)
		if not ui.achievements_menu_requested.is_connected(_on_achievements_menu_requested):
			ui.achievements_menu_requested.connect(_on_achievements_menu_requested)
		if not ui.restart_requested.is_connected(_on_ui_restart_requested):
			ui.restart_requested.connect(_on_ui_restart_requested)
		ui.set_initial_skin(saved_skin)
	
	if achievements and not achievements.achievement_unlocked.is_connected(_on_achievement_unlocked):
		achievements.achievement_unlocked.connect(_on_achievement_unlocked)

func _process(delta: float) -> void:
	if is_night and state == GameState.PLAYING and lightning_flash:
		lightning_timer -= delta
		if lightning_timer <= 0.0:
			lightning_timer = randf_range(11.0, 19.0)
			trigger_lightning()

	if state == GameState.PLAYING and weather != Weather.NONE:
		weather_time_left -= delta
		weather_elapsed += delta
		# Rüzgarda kuş hafifçe yalpalar
		if bird and (weather == Weather.TAILWIND or weather == Weather.HEADWIND):
			var dir = 1.0 if weather == Weather.TAILWIND else -1.0
			bird.position.x = bird_base_x + sin(weather_elapsed * 7.0) * 6.0 * dir
		if weather_time_left <= 0.0:
			_clear_weather(true)

func trigger_lightning() -> void:
	if not lightning_flash:
		return
	var tween = create_tween()
	tween.tween_property(lightning_flash, "color:a", 0.75, 0.06)
	tween.tween_property(lightning_flash, "color:a", 0.15, 0.05)
	tween.tween_property(lightning_flash, "color:a", 0.65, 0.05)
	tween.tween_property(lightning_flash, "color:a", 0.0, 0.15)

# --- HAVA OLAYLARI (rüzgar / sis) ---
func _build_weather_nodes() -> void:
	wind_particles = CPUParticles2D.new()
	wind_particles.amount = 28
	wind_particles.lifetime = 0.9
	wind_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	wind_particles.emission_rect_extents = Vector2(150, 260)
	wind_particles.position = Vector2(144, 256)
	wind_particles.direction = Vector2(-1, 0)
	wind_particles.spread = 8.0
	wind_particles.gravity = Vector2.ZERO
	wind_particles.initial_velocity_min = 260.0
	wind_particles.initial_velocity_max = 340.0
	wind_particles.color = Color(1, 1, 1, 0.35)
	wind_particles.z_index = 4
	wind_particles.emitting = false
	add_child(wind_particles)

	fog_rect = ColorRect.new()
	fog_rect.color = Color(0.75, 0.82, 0.9, 0.0)
	fog_rect.offset_right = 288.0
	fog_rect.offset_bottom = 512.0
	fog_rect.z_index = 15
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog_rect)

	if bird:
		bird_base_x = bird.position.x

func _maybe_trigger_weather() -> void:
	if state != GameState.PLAYING or boss_active or weather != Weather.NONE:
		return
	var roll = randf()
	if roll < 0.35:
		_start_weather(Weather.TAILWIND)
	elif roll < 0.65:
		_start_weather(Weather.HEADWIND)
	else:
		_start_weather(Weather.FOG)

func _start_weather(w: Weather) -> void:
	weather = w
	weather_time_left = WEATHER_DURATION
	weather_elapsed = 0.0
	match w:
		Weather.TAILWIND:
			_set_wind_bonus(45.0)
			wind_particles.direction = Vector2(-1, 0)
			wind_particles.emitting = true
			ui.show_weather_banner("💨 ARKA RÜZGAR! Borular hızlı!")
		Weather.HEADWIND:
			_set_wind_bonus(-45.0)
			wind_particles.direction = Vector2(1, 0)
			wind_particles.emitting = true
			ui.show_weather_banner("💨 KARŞI RÜZGAR! Borular yavaş!")
		Weather.FOG:
			var tween = create_tween()
			tween.tween_property(fog_rect, "color:a", 0.5, 0.8)
			ui.show_weather_banner("🌫️ SİS! Önünü gör!")
	audio_manager.play_swoosh()

func _set_wind_bonus(value: float) -> void:
	# Rüzgar değişince SADECE yeni borular değil, ekrandaki tüm borular
	# aynı hıza geçer — yoksa hızlı boru yavaşı yakalayıp üst üste biner.
	var delta = value - wind_pipe_bonus
	wind_pipe_bonus = value
	if pipe_spawner:
		pipe_spawner.wind_speed_bonus = value
	if absf(delta) > 0.001 and pipes_container:
		for child in pipes_container.get_children():
			if child is PipePair:
				child.speed = maxf(child.speed + delta, 60.0)
			elif child is PowerUp:
				child.speed = maxf(child.speed + delta, 40.0)
	if ground:
		ground.speed = maxf(120.0 + minf(float(score) * 0.8, 35.0) + value, 60.0)

func _clear_weather(survived: bool) -> void:
	if weather == Weather.NONE:
		return
	var was_wind = (weather == Weather.TAILWIND or weather == Weather.HEADWIND)
	var was_fog = (weather == Weather.FOG)
	weather = Weather.NONE
	_set_wind_bonus(0.0)
	if pipe_spawner:
		pipe_spawner.set_game_state_data(score, is_night)
	if wind_particles:
		wind_particles.emitting = false
	if fog_rect:
		var tween = create_tween()
		tween.tween_property(fog_rect, "color:a", 0.0, 0.5)
	if bird and state == GameState.PLAYING:
		bird.position.x = bird_base_x
	if survived and state == GameState.PLAYING and achievements:
		if was_wind:
			achievements.unlock("storm_rider")
		elif was_fog:
			achievements.unlock("fog_navigator")

func _input(event: InputEvent) -> void:
	if state == GameState.GAME_OVER and can_restart:
		if (event is InputEventScreenTouch and event.pressed) or \
		   (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or \
		   event.is_action_pressed("flap") or event.is_action_pressed("restart"):
			get_viewport().set_input_as_handled()
			restart_game()

func _on_ui_restart_requested() -> void:
	if state == GameState.GAME_OVER and can_restart:
		restart_game()

func _unhandled_input(event: InputEvent) -> void:
	var is_action = event.is_action_pressed("flap") or \
	                event.is_action_pressed("restart") or \
	                (event is InputEventScreenTouch and event.pressed) or \
	                (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_action:
		if ui and ui.achievements_modal and ui.achievements_modal.visible:
			ui.close_achievements_modal()
			return
		if ui and ui.profile_modal and ui.profile_modal.visible:
			return
		
		match state:
			GameState.READY:
				start_game()
			GameState.PLAYING:
				bird.flap()
				audio_manager.play_wing()
			GameState.GAME_OVER:
				if can_restart:
					restart_game()

func _on_achievements_menu_requested() -> void:
	if achievements and ui:
		ui.open_achievements_modal(achievements.ACHIEVEMENTS, achievements.unlocked_ids)

func start_game() -> void:
	state = GameState.PLAYING
	ui.hide_message()
	bird.start_flying()
	audio_manager.play_wing()
	if audio_manager.has_method("play_bgm"):
		audio_manager.play_bgm()
	pipe_spawner.set_game_state_data(score, is_night)
	pipe_spawner.start()

func _on_skin_changed(skin_name: String) -> void:
	saved_skin = skin_name
	bird.set_skin(skin_name)
	save_save_data()

func _on_pipe_spawned(pipe: PipePair) -> void:
	pipes_container.add_child(pipe)
	pipe.score_awarded.connect(_on_score_awarded)
	pipe.perfect_score_awarded.connect(_on_perfect_score_awarded)
	pipe.bird_hit.connect(_on_bird_died)

func _on_powerup_spawned(powerup: PowerUp) -> void:
	pipes_container.add_child(powerup)

func _on_shield_absorbed() -> void:
	audio_manager.play_hit()
	shake_camera(0.15, 3.5)
	if achievements:
		achievements.unlock("shield_master")

func _on_double_score_toggled(active: bool) -> void:
	ui.set_double_score_indicator(active)
	if active and achievements:
		achievements.unlock("star_power")

func _on_perfect_score_awarded(pos: Vector2) -> void:
	if state != GameState.PLAYING:
		return
	
	var is_double = bird.is_double_score if bird else false
	var bonus_points = 3 if is_double else 2
	score += bonus_points
	ui.update_score(score)
	ui.show_perfect_indicator(pos)
	audio_manager.play_point()
	
	if achievements:
		achievements.unlock("perfectionist")
	
	_check_score_events()

func _on_score_awarded() -> void:
	if state != GameState.PLAYING:
		return
	
	var is_double = bird.is_double_score if bird else false
	var points_to_add = 2 if is_double else 1
	score += points_to_add
	ui.update_score(score)
	ui.spawn_score_popup(bird.global_position, "+%d" % points_to_add)
	audio_manager.play_point()
	
	_check_score_events()

func _check_score_events() -> void:
	# Achievement checks
	if score >= 5 and achievements:
		achievements.unlock("first_flight")
	if score >= 30 and achievements:
		achievements.unlock("legend")
	
	# Day / Night cycle logic (switches every 10 points)
	var new_night = ((score / 10) % 2 == 1)
	if new_night != is_night:
		is_night = new_night
		_transition_day_night(is_night)
		if is_night and achievements:
			achievements.unlock("night_owl")
	
	# Boss Encounter trigger every 100 points (100, 200, 300, etc.)
	if score >= next_boss_score and not boss_active:
		boss_active = true
		boss_level += 1
		next_boss_score += 100
		start_boss_encounter()

	# Weather event trigger (boss sırasında değil)
	if score >= next_weather_score:
		next_weather_score = score + randi_range(8, 13)
		_maybe_trigger_weather()

	pipe_spawner.set_game_state_data(score, is_night)

	var new_speed = 120.0 + minf(float(score) * 0.8, 35.0)
	ground.speed = new_speed + wind_pipe_bonus

func start_boss_encounter() -> void:
	pipe_spawner.stop()
	ui.show_boss_warning()
	shake_camera(0.6, 3.5)
	audio_manager.play_hit()
	if audio_manager.has_method("play_boss_music"):
		audio_manager.play_boss_music()
	
	# Wait for warning banner and remaining pipes to clear
	get_tree().create_timer(2.2).timeout.connect(func():
		if state != GameState.PLAYING:
			return
		
		var boss = boss_scene.instantiate() as MechaBoss
		if boss_level > 1:
			boss.max_health = mini(3 + (boss_level - 1), 5)
			boss.health = boss.max_health
		
		pipes_container.add_child(boss)
		current_boss = boss
		
		boss.health_changed.connect(_on_boss_health_changed)
		boss.defeated.connect(_on_boss_defeated)
		boss.shoot_projectile.connect(_on_boss_shoot_projectile)
		boss.spawn_bomb.connect(_on_boss_spawn_bomb)
		
		ui.update_boss_health(boss.health, boss.max_health)
	)

func _on_boss_shoot_projectile(spawn_pos: Vector2) -> void:
	if state != GameState.PLAYING:
		return
	var proj = boss_projectile_scene.instantiate() as BossProjectile
	proj.global_position = spawn_pos
	pipes_container.add_child(proj)

func _on_boss_spawn_bomb(spawn_pos: Vector2) -> void:
	if state != GameState.PLAYING:
		return
	var bomb = boss_bomb_scene.instantiate() as BossBomb
	bomb.global_position = spawn_pos
	pipes_container.add_child(bomb)

func _on_boss_health_changed(current_hp: int, max_hp: int) -> void:
	ui.update_boss_health(current_hp, max_hp)
	if current_hp < max_hp:
		audio_manager.play_hit()
		shake_camera(0.25, 4.5)

func _on_boss_defeated() -> void:
	current_boss = null
	boss_active = false
	score += 10
	ui.update_score(score)
	ui.show_boss_defeated()
	audio_manager.play_point()
	if audio_manager.has_method("fade_back_to_bgm"):
		audio_manager.fade_back_to_bgm()
	shake_camera(0.6, 6.0)
	
	if achievements:
		achievements.unlock("boss_slayer")
	
	# Resume pipes after victory celebration
	if is_inside_tree():
		var tree = get_tree()
		if tree:
			tree.create_timer(2.5).timeout.connect(func():
				if state == GameState.PLAYING:
					pipe_spawner.start()
			)

func _transition_day_night(night: bool) -> void:
	if background:
		var target_tex = night_texture if night else day_texture
		var tween = create_tween()
		tween.tween_property(background, "modulate:a", 0.4, 0.3)
		tween.tween_callback(func():
			background.texture = target_tex
		)
		tween.tween_property(background, "modulate:a", 1.0, 0.3)
	
	if rain_particles:
		rain_particles.emitting = night

func _on_achievement_unlocked(_id: String, info: Dictionary) -> void:
	ui.show_achievement_banner(info)
	audio_manager.play_point()

func _on_ground_hit() -> void:
	bird.die()

func _on_bird_died() -> void:
	if state == GameState.GAME_OVER:
		return
	
	state = GameState.GAME_OVER
	if audio_manager.has_method("stop_music"):
		audio_manager.stop_music()
	audio_manager.play_hit()
	shake_camera(0.25, 5.0)
	
	ground.stop()
	pipe_spawner.stop()
	for child in pipes_container.get_children():
		if child.has_method("stop"):
			child.stop()

	_clear_weather(false)
	
	get_tree().create_timer(0.18).timeout.connect(func():
		audio_manager.play_die()
	)
	
	var is_new_record = false
	if score > high_score:
		high_score = score
		is_new_record = true
		save_save_data()

	# Global sıralamaya skoru gönder (bağlı değilsek sessizce atlanır)
	NetworkManager.submit_rank_score(score)

	ui.show_game_over(score, high_score, is_new_record)
	
	get_tree().create_timer(0.4).timeout.connect(func():
		can_restart = true
	)

func shake_camera(duration: float, magnitude: float) -> void:
	if not camera:
		return
	var initial_offset = camera.offset
	var tween = create_tween()
	var steps = 6
	var step_time = duration / steps
	for i in range(steps):
		var target_offset = Vector2(
			randf_range(-magnitude, magnitude),
			randf_range(-magnitude, magnitude)
		)
		tween.tween_property(camera, "offset", target_offset, step_time)
	tween.tween_property(camera, "offset", initial_offset, step_time)

func restart_game() -> void:
	audio_manager.play_swoosh()
	get_tree().reload_current_scene()

func load_save_data() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		high_score = config.get_value("game", "high_score", 0)
		saved_skin = config.get_value("game", "skin", "yellow")

func save_save_data() -> void:
	var config = ConfigFile.new()
	var _err = config.load(SAVE_PATH)
	config.set_value("game", "high_score", high_score)
	config.set_value("game", "skin", saved_skin)
	config.save(SAVE_PATH)
