extends Node2D
class_name PipePair

signal bird_hit
signal score_awarded
signal perfect_score_awarded(pos: Vector2)

@export var speed: float = 120.0
@export var is_oscillating: bool = false
@export var oscillation_amplitude: float = 28.0
@export var oscillation_speed: float = 2.0

@onready var top_pipe_sprite: Sprite2D = $TopPipe/Sprite2D
@onready var bottom_pipe_sprite: Sprite2D = $BottomPipe/Sprite2D
@onready var top_pipe_collision: CollisionShape2D = $TopPipe/CollisionShape2D
@onready var bottom_pipe_collision: CollisionShape2D = $BottomPipe/CollisionShape2D

var is_moving: bool = true
var scored: bool = false
var base_y: float = 0.0
var oscillation_time: float = 0.0

func _ready() -> void:
	base_y = position.y

func set_red_theme(use_red: bool) -> void:
	if not top_pipe_sprite or not bottom_pipe_sprite:
		await ready
	var tex_path = "res://assets/sprites/pipe-red.png" if use_red else "res://assets/sprites/pipe-green.png"
	var tex = load(tex_path) as Texture2D
	if tex:
		top_pipe_sprite.texture = tex
		bottom_pipe_sprite.texture = tex

func _physics_process(delta: float) -> void:
	if not is_moving:
		return
	
	position.x -= speed * delta
	
	if is_oscillating:
		oscillation_time += delta * oscillation_speed
		position.y = clampf(base_y + sin(oscillation_time) * oscillation_amplitude, 140.0, 340.0)
	
	if position.x < -80.0:
		queue_free()

func stop() -> void:
	is_moving = false

func _on_pipe_body_entered(body: Node2D) -> void:
	if body is Bird and not body.is_dead:
		var absorbed = body.hit_by_obstacle()
		if absorbed:
			if top_pipe_collision:
				top_pipe_collision.set_deferred("disabled", true)
			if bottom_pipe_collision:
				bottom_pipe_collision.set_deferred("disabled", true)
			var tween = create_tween()
			tween.tween_property(self, "modulate:a", 0.3, 0.2)
		else:
			bird_hit.emit()

func _on_score_zone_body_entered(body: Node2D) -> void:
	if body is Bird and not scored and not body.is_dead:
		scored = true
		# Check if pass was within the center 17px of the gap
		var diff = absf(body.global_position.y - global_position.y)
		if diff <= 17.0:
			perfect_score_awarded.emit(global_position)
		else:
			score_awarded.emit()
