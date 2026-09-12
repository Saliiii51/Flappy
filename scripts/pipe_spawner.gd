extends Node2D
class_name PipeSpawner

signal pipe_spawned(pipe_pair: PipePair)
signal powerup_spawned(powerup: PowerUp)

@export var pipe_scene: PackedScene
@export var spawn_interval: float = 1.45
@export var min_gap_y: float = 160.0
@export var max_gap_y: float = 320.0

@onready var timer: Timer = $SpawnTimer

var is_spawning: bool = false
var current_score: int = 0
var is_night: bool = false

var powerup_scene: PackedScene = preload("res://scenes/powerup.tscn")

func start() -> void:
	is_spawning = true
	if timer:
		timer.wait_time = spawn_interval
		timer.start()

func stop() -> void:
	is_spawning = false
	if timer:
		timer.stop()

func set_game_state_data(score: int, night_mode: bool) -> void:
	current_score = score
	is_night = night_mode

func _on_spawn_timer_timeout() -> void:
	if not is_spawning or not pipe_scene:
		return
	
	var pipe = pipe_scene.instantiate() as PipePair
	var random_y = randf_range(min_gap_y, max_gap_y)
	pipe.position = Vector2(340.0, random_y)
	
	# Difficulty speed scaling
	var current_speed = 120.0 + minf(float(current_score) * 0.8, 35.0)
	pipe.speed = current_speed
	
	# Set theme (green / red)
	pipe.set_red_theme(is_night)
	
	# Dynamic oscillation chance
	if current_score >= 10:
		var oscillate_chance = 0.35 if current_score < 25 else 0.60
		if randf() < oscillate_chance:
			pipe.is_oscillating = true
			pipe.oscillation_speed = randf_range(1.8, 2.5)
	
	pipe_spawned.emit(pipe)
	
	# Random power-up spawn chance (~22%)
	if randf() < 0.22 and powerup_scene:
		var p_up = powerup_scene.instantiate() as PowerUp
		var p_type = PowerUp.Type.SHIELD if randf() < 0.55 else PowerUp.Type.DOUBLE_SCORE
		p_up.setup_type(p_type)
		p_up.position = Vector2(340.0 + 35.0, random_y)
		p_up.speed = current_speed
		powerup_spawned.emit(p_up)
